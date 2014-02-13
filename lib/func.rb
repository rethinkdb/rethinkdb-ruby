module RethinkDB
  class RQL
    @@gensym_cnt = 0
    def new_func(&b)
      args = (0...b.arity).map{@@gensym_cnt += 1}
      body = b.call(*(args.map{|i| RQL.new.var i}))
      RQL.new.func(args, body)
    end

    # Offsets of the "optarg" optional arguments hash in respective
    # methods.  Some methods change this depending on whether they're
    # passed a block -- they take a hash specifying the offset for
    # each circumstance, instead of an integer.  -1 can be supplied to
    # mean the "last" argument -- whatever argument is specified will
    # only be removed from the argument list and treated as an optarg
    # if it's a Hash.  A positive value is necessary for functions
    # that can take a hash for the last non-optarg argument.
    # NOTE: we search for the optarg after we apply the rewrite rules below.
    # For example we need to use orderby not order_by
    @@optarg_offsets = {
      :replace => {:with_block => 0, :without => 1},
      :update => {:with_block => 0, :without => 1},
      :insert => 1,
      :delete => -1,
      :reduce => -1, :between => 2, :grouped_map_reduce => -1,
      :table => -1, :table_create => -1,
      :get_all => -1, :eq_join => -1,
      :javascript => -1, :filter => {:with_block => 0, :without => 1},
      :slice => -1, :during => -1, :orderby => -1,
      :iso8601 => -1, :index_create => -1
    }
    @@rewrites = {
      :< => :lt, :<= => :le, :> => :gt, :>= => :ge,
      :+ => :add, :- => :sub, :* => :mul, :/ => :div, :% => :mod,
      :"|" => :any, :or => :any,
      :"&" => :all, :and => :all,
      :order_by => :orderby,
      :group_by => :groupby,
      :concat_map => :concatmap,
      :for_each => :foreach,
      :js => :javascript,
      :type_of => :typeof
    }
    @@allow_json = {:insert => true}
    def method_missing(m, *a, &b)
      unbound_if(m.to_s.downcase != m.to_s, m)
      bitop = [:"|", :"&"].include?(m) ? [m, a, b] : nil
      if [:<, :<=, :>, :>=, :+, :-, :*, :/, :%].include?(m)
        a.each {|arg|
          if arg.class == RQL && arg.bitop
            err = "Calling #{m} on result of infix bitwise operator:\n" +
              "#{arg.inspect}.\n" +
              "This is almost always a precedence error.\n" +
              "Note that `a < b | b < c` <==> `a < (b | b) < c`.\n" +
              "If you really want this behavior, use `.or` or `.and` instead."
            raise RqlDriverError, err
          end
        }
      end

      old_m = m
      m = @@rewrites[m] || m
      begin
        termtype = Term::TermType.const_get(m.to_s.upcase)
      rescue NameError => e
        unbound_if(true, old_m)
      end
      unbound_if(!termtype, m)

      if (opt_offset = @@optarg_offsets[m])
        if opt_offset.class == Hash
          opt_offset = opt_offset[b ? :with_block : :without]
        end
        # TODO: This should drop the Hash comparison or at least
        # @@optarg_offsets should stop specifying -1, where possible.
        # Any time one of these operations is changed to support a
        # hash argument, we'll have to remember to fix
        # @@optarg_offsets, otherwise.
        optargs = a.delete_at(opt_offset) if a[opt_offset].class == Hash
      end

      args = (@body ? [self] : []) + a + (b ? [new_func(&b)] : [])

      t = Term.new
      t.type = termtype
      t.args = args.map{|x| RQL.new.expr(x, :allow_json => @@allow_json[m]).to_pb}
      t.optargs = (optargs || {}).map {|k,v|
        ap = Term::AssocPair.new
        ap.key = k.to_s
        ap.val = RQL.new.expr(v, :allow_json => @@allow_json[m]).to_pb
        ap
      }
      return RQL.new(t, bitop)
    end

    def group_by(*a, &b)
      a = [self] + a if @body
      RQL.new.method_missing(:group_by, a[0], a[1..-2], a[-1], &b)
    end
    def groupby(*a, &b); group_by(*a, &b); end

    def connect(*args, &b)
      unbound_if @body
      c = Connection.new(*args)
      b ? begin b.call(c) ensure c.close end : c
    end

    def -@; RQL.new.sub(0, self); end

    def [](ind)
      if ind.class == Fixnum
        return nth(ind)
      elsif ind.class == Symbol || ind.class == String
        return get_field(ind)
      elsif ind.class == Range
        return slice(ind.begin, ind.end, :right_bound =>
                     (ind.exclude_end? ? 'open' : 'closed'))
      end
      raise ArgumentError, "[] cannot handle #{ind.inspect} of type #{ind.class}."
    end

    def ==(rhs)
      raise ArgumentError,"
      Cannot use inline ==/!= with RQL queries, use .eq() instead if
      you want a query that does equality comparison.

      If you need to see whether two queries are the same, compare
      their protobufs like: `query1.to_pb == query2.to_pb`."
    end


    def do(*args, &b)
      a = (@body ? [self] : []) + args.dup
      if a == [] && !b
        raise RqlDriverError, "Expected 1 or more argument(s) but found 0."
      end
      RQL.new.funcall(*((b ? [new_func(&b)] : [a.pop]) + a))
    end

    def row
      unbound_if @body
      raise NoMethodError, ("Sorry, r.row is not available in the ruby driver.  " +
                            "Use blocks instead.")
    end
  end
end
