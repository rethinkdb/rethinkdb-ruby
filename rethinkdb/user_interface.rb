# Right now, this is a place to record high-level spec changes that need to
# happen.  TODO:
# * UPDATE needs to be changed to do an implicit mapmerge on its righthand side
#   (this will make its behavior line up with the Python documentation).
# * MUTATE needs to be renamed to REPLACE (Joe and Tim and I just talked about
#   this) and maintain its current behavior rather than changing to match UPDATE.
# * The following are currently unimplemented or buggy: REDUCE, GROUPEDMAPREDUCE,
#   MUTATE, FOREACH, POINTUPDATE, POINTMUTATE.
# * The following are going away: ARRAYAPPEND, ARRAYCONCAT, ARRAYSLICE,
#   ARRAYNTH, ARRAYLENGTH (to be replaced with APPEND, UNION, SLICE, NTH, and
#   LENGTH (all polymorphic, some of which already work for streams)).
# * I don't understand where JAVASCRIPT is used, or how GROUPEDMAPREDUCE works.
module RethinkDB
  # A network connection to the RethinkDB cluster.
  class Connection
    # Create a new connection to <b>+host+</b> on port <b>+port+</b>.  Example:
    #   c = Connection.new('localhost')
    def initialize(host, port=12346)
      @@last = self
      @socket = TCPSocket.open(host, port)
      @waiters = {}
      @data = {}
      @mutex = Mutex.new
      start_listener
    end

    # Run the RQL query <b>+query+</b>.  Returns either a list of JSON values or
    # a single JSON value depending on <b>+query+</b>.  (Note that JSON values
    # will be converted to Ruby datatypes by the time you receive them.)
    # Example (assuming a connection <b>+c+</b> and that you've mixed in
    # shortcut <b>+r+</b>):
    #   c.run(r.add(1,2))                         => 3
    #   c.run(r.expr([r.add(1,2)]))               => [3]
    #   c.run(r.expr([r.add(1,2), r.add(10,20)])) => [3, 30]
    def run query
      a = []
      token_iter(dispatch query){|row| a.push row} ? a : a[0]
    end

    # Run the RQL query <b>+query+</b> and iterate over the results.  The
    # <b>+block+</b> you provide should take a single argument, which will be
    # bound to a single JSON value each time your block is invoked.  Returns
    # <b>+true+</b> if your query returned a sequence of values or
    # <b>+false+</b> if your query returned a single value.  (Note that JSON
    # values will be converted to Ruby datatypes by the time you receive them.)
    # Example (assuming a connection <b>+c+</b> and that you've mixed in
    # shortcut <b>+r+</b>):
    #   a = []
    #   c.iter(r.add(1,2)) {|val| a.push val} => false
    #   a                                     => [3]
    #   c.iter(r.expr([r.add(1,2), r.add(10,20)])) {|val| a.push val} => false
    #   a                                     => [3]
    def iter(query, &block)
      token_iter(dispatch(query), &block)
    end

    # Close the connection.
    def close
      @listener.terminate!
      @socket.close
    end
  end

  # An RQL query that can be sent to the RethinkDB cluster.  Queries are either
  # constructed by methods in the RQL module, or by invoking the instance
  # methods of a query on other queries.
  #
  # When the instance methods of queries are invoked on native Ruby datatypes
  # rather than other queries, the RethinkDB library will attempt to convert the
  # Ruby datatype to a query.  Numbers, strings, booleans, and nil will all be
  # converted to query types, but arrays and objects need to be converted
  # explicitly with either the <b>+expr+</b> or <b><tt>[]</tt></b> methods in
  # the RQL module.
  class RQL_Query
    # Construct a query that deletes all rows of the invoking query.  For
    # example, if we have a table <b>+table+</b>:
    #   table.filter{|row| row[:id] < 5}.delete
    # will construct a query that deletes everything with <b>+id+</b> less than
    # 5 in <b>+table+</b>
    def delete; S._ [:delete, @body]; end

    # Construct a query which updates all rows of the invoking query.  For
    # example, if we have a table <b>+table+</b>:
    #   table.filter{|row| row[:id] < 5}.update{|row| {:score => row[:score]*2}}
    # will construct a query that doubles the score of everything with
    # <b>+id+</b> less tahn 4.  If the object returned in <b>+update+</b>
    # has attributes which are not present in the original row, those attributes
    # will still be added to the new row.
    def update; S.with_var {|vname,v| S._ [:update, @body, [vname, yield(v)]]}; end

    # Construct a query which filters the invoking query using some predicate.
    # You may either specify the predicate explicitly by providing a block which
    # takes a single argument (the row you're testing), or provide an object
    # <b>+obj+</b>.  If you provide an object, it will match JSON objects which
    # match its attributes.  For example, if we have a table <b>+people+</b>,
    # the following two queries are equivalent:
    #   people.filter{|row| row[:name].eq('Bob') & row[:age].eq(50)}
    #   people.filter({:name => 'Bob', :age => 50})
    # Note that the values of attributes may themselves be rdb queries.  For
    # instance, here is a query that maches anyone whose age is double their height:
    #   people.filter({:age => r[:height]*2})

    # (The <b><tt>r[:height]</tt></b> references the Implicit Variable, see
    # RQL_Mixin#expr.)
    def filter(obj=nil)
      if obj then filter{[:call, [:all], obj.map {|kv| RQL.attr(kv[0]).eq(kv[1])}]}
             else S.with_var {|vname,v| S._ [:call, [:filter, vname, yield(v)], [@body]]}
      end
    end

    #TODO: LIMIT (ask about SLICE)

    # Construct a query which maps a function over the invoking query.  It is
    # often used in conjunction with <b>+reduce+</b>. For example, if we have a
    # table <b>+table+</b>:
    #   table.map{|row| row[:age]}.reduce(0){|a,b| a+b}
    # will add up all the ages in <b>+table+</b>.
    def map; S.with_var {|vname,v| S._ [:call, [:map, vname, yield(v)], [@body]]}; end

    # Construct a query which selects the nth element of the invoking query.
    # For example, if we have a table <b>+people+</b>:
    #   people.filter{|row| row[:age] < 5}.nth(0)
    # Will get the first person under 5 in our table (it's 0-indexed).
    #
    # TODO: Support [] notation?
    def nth(n); S._ [:call, [:nth], [@body, n]]; end

    # Order the invoking query.  For example, to sort first by name and then by
    # social security number for the table <b>+people+</b>:
    #   people.orderby(:name, :ssn)
    #
    # TODO: notation for reverse ordering
    def orderby(*orderings); S._ [:call, [:orderby, *orderings], [@body]]; end

    #TODO: Random (unimplemented)
    #TODO: Reduce (unimplemented)

    # Run the invoking query using the most recently opened connection.  See
    # Connection#run for more details.
    def run; connection_send :run; end
    # Run the invoking query and iterate over the results using the most
    # recently opened connection.  See Connection#iter for more details.
    def iter; connection_send :iter; end

    #TODO: Sample (unimplemented)
    #TODO: SKIP (ask about SLICE)

    # Get the row of the invoking table with key <b>+key+</b>.  You may also
    # optionally specify the name of the attribute to use as your key
    # (<b>+keyname+</b>), but note that your table must be indexed by that
    # attribute.  Calling this function on anything except a table is an error:
    #   good = table.get(0)
    #   bad  = table.filter{|row| row[:name] = 'Bob'}.get(0)
    # TODO: get().delete() => pointdelete
    def get(key, keyname=:id)
      if @body[0] == :table then S._ [:getbykey, @body[1..-1], keyname, key]
                            else raise SyntaxError, "Get must be called on a table."
      end
    end
  end

  # A mixin that contains all the query building commands.  Usually you will
  # access these functions by extending/including <b>+Shortcuts_Mixin+</b> and
  # then using the shortcut <b>+r+</b> that it provides.  For example, assuming
  # you have <b>+r+</b> available and have opened a connection to a cluster with
  # the namespace 'Welcome', you could do something like:
  #   r.db('').Welcome.limit(4).run
  # to get the first 4 elements of that namespace.
  module RQL_Mixin
    # Construct a new table reference, which may then be treated as a query for
    # chaining (see the functions in RQL_Query).  There are two identical ways
    # of getting access to a namespace: passing it as the second argument, or
    # calling it as an instance method if no second argument was provided.  For
    # instance, to access the namespace Welcome, either of these works:
    #   db('','Welcome')
    #   db('').Welcome
    def db(db_name, table_name=nil); Tbl.new db_name, table_name; end

    # A shortcut for RQL_Mixin#expr.  The following are equivalent:
    #   r.expr(5)
    #   r[5]
    def [](ind); expr ind; end

    # Convert from a Ruby datatype to an RQL query.  More commonly accessed
    # with its shortcut, <b><tt>[]</tt></b>.  Numbers, strings, booleans,
    # arrays, objects, and nil are all converted to their respective JSON types.
    # Symbols that begin with '$' are converted to variables, and symbols
    # without a '$' are converted to attributes of the implicit variable.  The
    # implicit variable is defined for most operations as the current row.  For
    # example, the following are equivalent:
    #   r.db('').Welcome.filter{|row| row[:id].eq(5)}
    #   r.db('').Welcome.filter{r.expr(:id).eq(5)}
    #   r.db('').Welcome.filter{r[:id].eq(5)}
    # Variables are used in e.g. <b>+let+</b> bindings.  For example:
    #   r.let([['a', 1],
    #          ['b', r[:$a]+1]],
    #         r[:$b]*2).run
    # will return 4.  (This notation will usually result in editors highlighting
    # your variables the same as global ruby variables, which makes them stand
    # out nicely in queries.)
    #
    # Note: this function is idempotent, so the following are equivalent:
    #   r[5]
    #   r[r[5]]
    # Note 2: the implicit variable can be dangerous.  Never pass it to a
    # Ruby function, as it might enter a different scope without your
    # knowledge.  In general, if you're doing something complicated, consider
    # naming your variables.
    def expr x
      case x.class().hash
      when RQL_Query.hash  then x
      when String.hash     then S._ [:string, x]
      when Fixnum.hash     then S._ [:number, x]
      when TrueClass.hash  then S._ [:bool, x]
      when FalseClass.hash then S._ [:bool, x]
      when NilClass.hash   then S._ [:json_null]
      when Array.hash      then S._ [:array, *x.map{|y| expr(y)}]
      when Hash.hash       then S._ [:object, *x.map{|var,term| [var, expr(term)]}]
      when Symbol.hash     then S._ x.to_s[0]=='$'[0] ? var(x.to_s[1..-1]) : getattr(x)
      else raise TypeError, "RQL.expr can't handle '#{x.class()}'"
      end
    end

    # Explicitly construct an RQL variable from a string.  The following are
    # equivalent:
    #   r[:$varname]
    #   r.var('varname')
    def var(varname); S._ [:var, varname]; end

    # Provide a literal JSON string that will be parsed by the server.  For
    # example, the following are equivalent:
    #   r.expr([1,2,3])
    #   r.json('[1,2,3]')
    def json(str); S._ [:json, str]; end

    # Construct an error.  This is usually used in the branch of an <b>+if+</b>
    # expression.  For example:
    #   r.if(r[1] > 2, false, r.error('unreachable'))
    # will only run the error query if 1 is greater than 2.  If an error query
    # does get run, it will be received as a RuntimeError in Ruby, so be
    # prepared to handle it.
    def error(err); S._ [:error, err]; end

    # Construct a query that runs a subquery <b>+test+</b> which returns a
    # boolean, then branches into either <b>+t_branch+</b> if <b>+test+</b>
    # returned true or <b>+f_branch+</b> if <b>+test+</b> returned false.  For
    # example, if we have a table <b>+table+</b>:
    #   table.update{|row| if(row[:score] < 10, {:score => 10}, {})}
    # will change every row with score below 10 in <b>+table+</b> to have score 10.
    def if(test, t_branch, f_branch); S._ [:if, test, t_branch, f_branch]; end

    # Construct a query that binds some values to variable (as specified by
    # <b>+varbinds+</b>) and then executes <b>+body+</b> with those variables in
    # scope.  For example:
    #   r.let([['a', 2],
    #          ['b', r[:$a]+1]],
    #         r[:$b]*2)
    # will bind <b>+a+</b> to 2, <b>+b+</b> to 3, and then return 6.  (It is
    # thus analagous to <b><tt>let*</tt></b> in the Lisp family of languages.)
    def let(varbinds, body); S._ [:let, varbinds, body]; end

    # Negate a predicate.  May also be called as if it were a member function of
    # RQL_Query for convenience.  The following are equivalent:
    #   r.not(true)
    #   r[true].not
    def not(pred); S._ [:call, [:not], [pred]]; end

    # Explicitly construct a reference to an attribute of the implicit
    # variable.  This is useful if for some reason you named an attribute that's
    # hard to express as a symbol, or an attribute starting with a '$'.  The
    # following are equivalent:
    #   r[:attrname]
    #   r.attr('attrname')
    # Get an attribute of the implicit variable (usually done with
    # RQL_Mixin#expr).  Getting an attribute explicitly is useful if it has an
    # odd name that can't be expressed as a symbol (or a name that starts with a
    # $).  Synonyms are <b>+get+</b> and <b>+attr+</b>.  The following are all
    # equivalent:
    #   r[:id]
    #   r.expr(:id)
    #   r.getattr('id')
    #   r.get('id')
    #   r.attr('id')
    def getattr(attrname); S._ [:call, [:implicit_getattr, attrname], []]; end

    # Test whether the implicit variable has a particular attribute.  Synonyms
    # are <b>+has+</b> and <b>+attr?+</b>.  The following are all equivalent:
    #   r.hasattr('name')
    #   r.has('name')
    #   r.attr?('name')
    def hasattr(attrname); S._ [:call, [:implicit_hasattr, attrname], []]; end

    # Construct an object that is a subset of the object stored in the implicit
    # variable by extracting certain attributes.  Synonyms are <b>+pick+</b> and
    # <b>+attrs+</b>.  The following are all equivalent:
    #   r[{:id => r[:id], :name => r[:name]}]
    #   r.pickattrs(:id, :name)
    #   r.pick(:id, :name)
    #   r.attrs(:id, :name)
    def pickattrs(*attrnames); [:call, [:implicit_pickattrs, *attrnames], []]; end

    # Add the results of two or more queries together.  (Those queries should
    # return numbers.)  May also be called as if it were a member function of
    # RQL_Query for convenience, and overloads <b><tt>+</tt></b> if the lefthand
    # side is a query.  The following are all equivalent:
    #   r.add(1,2)
    #   r[1].add(2)
    #   (r[1] + 2) # Note that (1 + r[2]) is *incorrect* because Ruby only
    #              # overloads based on the lefthand side.
    # The following is also legal:
    #   r.add(1,2,3)
    def add(a, b, *rest); S._ [:call, [:add], [a, b, *rest]]; end

    # Subtract one query from another.  (Those queries should return numbers.)
    # May also be called as if it were a member function of RQL_Query for
    # convenience, and overloads <b><tt>-</tt></b> if the lefthand side is a
    # query.  Also has the shorter synonym <b>+sub+</b>. The following are all
    # equivalent:
    #   r.subtract(1,2)
    #   r[1].subtract(2)
    #   r.sub(1,2)
    #   r[1].sub(2)
    #   (r[1] - 2) # Note that (1 - r[2]) is *incorrect* because Ruby only
    #              # overloads based on the lefthand side.
    def subtract(a, b); S._ [:call, [:subtract], [a, b]]; end

    # Multiply the results of two or more queries together.  (Those queries should
    # return numbers.)  May also be called as if it were a member function of
    # RQL_Query for convenience, and overloads <b><tt>+</tt></b> if the lefthand
    # side is a query.  Also has the shorter synonym <b>+mul+</b>.  The
    # following are all equivalent:
    #   r.multiply(1,2)
    #   r[1].multiply(2)
    #   r.mul(1,2)
    #   r[1].mul(2)
    #   (r[1] * 2) # Note that (1 * r[2]) is *incorrect* because Ruby only
    #              # overloads based on the lefthand side.
    # The following is also legal:
    #   r.multiply(1,2,3)
    def multiply(a, b, *rest); S._ [:call, [:multiply], [a, b, *rest]]; end

    # Divide one query by another.  (Those queries should return numbers.)
    # May also be called as if it were a member function of RQL_Query for
    # convenience, and overloads <b><tt>/</tt></b> if the lefthand side is a
    # query.  Also has the shorter synonym <b>+div+</b>. The following are all
    # equivalent:
    #   r.divide(1,2)
    #   r[1].divide(2)
    #   r.div(1,2)
    #   r[1].div(2)
    #   (r[1] / 2) # Note that (1 / r[2]) is *incorrect* because Ruby only
    #              # overloads based on the lefthand side.
    def divide(a, b); S._ [:call, [:divide], [a, b]]; end

    # Take one query modulo another.  (Those queries should return numbers.)
    # May also be called as if it were a member function of RQL_Query for
    # convenience, and overloads <b><tt>%</tt></b> if the lefthand side is a
    # query.  Also has the shorter synonym <b>+mod+</b>. The following are all
    # equivalent:
    #   r.modulo(1,2)
    #   r[1].modulo(2)
    #   r.mod(1,2)
    #   r[1].mod(2)
    #   (r[1] - 2) # Note that (1 - r[2]) is *incorrect* because Ruby only
    #              # overloads based on the lefthand side.
    def modulo(a, b); S._ [:call, [:modulo], [a, b]]; end

    # Take one or more predicate queries and construct a query that returns true
    # if any of them evaluate to true.  Sort of like <b>+or+</b> in ruby, but
    # takes arbitrarily many arguments and is *not* guaranteed to
    # short-circuit.  May also be called as if it were a member function of
    # RQL_Query for convenience, and overloads <b><tt>&</tt></b> if the lefthand
    # side is a query.  Also has the synonym <b>+or+</b>.  The following are
    # all equivalent:
    #   r[true]
    #   r.any(false, true)
    #   r.or(false, true)
    #   r[false].any(true)
    #   r[false].or(true)
    #   (r[false] & true) # Note that (false & r[true]) is *incorrect* because
    #                     # Ruby only overloads based on the lefthand side
    def any(pred, *rest); S._ [:call, [:any], [pred, *rest]]; end

    # Take one or more predicate queries and construct a query that returns true
    # if all of them evaluate to true.  Sort of like <b>+or+</b> in ruby, but
    # takes arbitrarily many arguments and is *not* guaranteed to
    # short-circuit.  May also be called as if it were a member function of
    # RQL_Query for convenience, and overloads <b><tt>|</tt></b> if the lefthand
    # side is a query.  Also has the synonym <b>+or+</b>.  The following are
    # all equivalent:
    #   r[false]
    #   r.all(false, true)
    #   r.and(false, true)
    #   r[false].all(true)
    #   r[false].and(true)
    #   (r[false] | true) # Note that (false | r[true]) is *incorrect* because
    #                     # Ruby only overloads based on the lefthand side
    def all(pred, *rest); S._ [:call, [:all], [pred, *rest]]; end

    # Filter a query returning a stream based on a predicate.  May also be
    # called as if it were a member function of RQL_Query for convenience.  The
    # provided block should take a single variable, a row in the stream, and
    # return either <b>+true+</b> if it should be in the resulting stream of
    # <b>+false+</b> otherwise.  If you have a table <b>+table+</b>, the
    # following are all equivalent:
    #   r.filter(table) {|row| row[:id] < 5}
    #   table.filter {|row| row[:id] < 5}
    #   table.filter {r[:id] < 5} # uses implicit variable
    def filter(stream)
      S.with_var{|vname,v| S._ [:call, [:filter, vname, yield(v)], [stream]]}
    end

    # Map a function over a query returning a stream.  May also be called as if
    # it were a member function of RQL_Query for convenience.  The provided
    # block should take a single variable, a row in the stream, and return a row
    # in the resulting stream.  If you have a table <b>+table+</b>, the
    # following are all equivalent:
    #   r.map(table) {|row| row[:id]}
    #   table.map {|row| row[:id]}
    #   table.map {r[:id]} # uses implicit variable
    def map(stream)
      S.with_var{|vname,v| S._ [:call, [:map, vname, yield(v)], [stream]]}
    end

    # Map a function over a query returning a stream, then concatenate the
    # results together.  May also be called as if it were a member function of
    # RQL_Query for convenience.  The provided block should take a single
    # variable, a row in the stream, and return a list of rows to include in the
    # resulting stream.  If you have a table <b>+table+</b>, the following are
    # all equivalent:
    #   r.concatmap(table) {|row| r.expr([row[:id], row[:id]*2])}
    #   table.concatmap {|row| r.expr([row[:id], row[:id]*2])}
    #   table.concatmap {r.expr([r[:id], r[:id]*2])} # uses implicit variable
    #   table.map{|row| r.expr([row[:id], row[:id]*2])}.reduce([]){|a,b| r.union(a,b)}
    def concatmap(stream)
      S.with_var{|vname,v| S._ [:call, [:concatmap, vname, yield(v)], [stream]]}
    end


    # TODO: start_inclusive, end_inclusive in python -- what do these do?
    #
    # Construct a query which yields all rows of <b>+stream+</b> with keys
    # between <b>+start_key+</b> and <b>+end_key+</b> (inclusive).  You may also
    # optionally specify the name of the attribute to use as your key
    # (<b>+keyname+</b>), but note that your table must be indexed by that
    # attribute.  Either <b>+start_key+</b> and <b>+end_key+</b> may be nil, in
    # which case that side of the range is unbounded.  This function may also be
    # called as if it were a member function of RQL_Query, for convenience.  For
    # example, if we have a table <b>+table+</b>, these are equivalent:
    #   r.between(table, 3, 7)
    #   table.between(3,7)
    #   table.filter{|row| (row[:id] >= 3) & (row[:id] <= 7)}
    # as are these:
    #   table.between(nil,7,:index)
    #   table.filter{|row| row[:index] <= 7}
    def between(stream, start_key, end_key, keyname=:id)
      opts = {:attrname => keyname}
      opts[:lowerbound] = start_key if start_key != nil
      opts[:upperbound] = end_key if end_key != nil
      S._ [:call, [:range, opts], [stream]]
    end
  end
end