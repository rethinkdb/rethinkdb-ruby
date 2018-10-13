describe "the docs examples" do
  it "can create and drop a table" do
    result = db.table_create('dc_universe').run(conn)
    expect(result).to include({"tables_created" => 1})
    result = db.table_drop('dc_universe').run(conn)
    expect(result).to include({"tables_dropped" => 1})
  end
end

describe "10-minute guide" do
  before :each do
    authors = r.table_create('authors').run
    result= r.table("authors").insert([
      { "name"=>"William Adama", "tv_show"=>"Battlestar Galactica",
        "posts"=>[
          {"title"=>"Decommissioning speech", "content"=>"The Cylon War is long over..."},
          {"title"=>"We are at war", "content"=>"Moments ago, this ship received..."},
          {"title"=>"The new Earth", "content"=>"The discoveries of the past few days..."}
        ]
      },
      { "name"=>"Laura Roslin", "tv_show"=>"Battlestar Galactica",
        "posts"=>[
          {"title"=>"The oath of office", "content"=>"I, Laura Roslin, ..."},
          {"title"=>"They look like us", "content"=>"The Cylons have the ability..."}
        ]
      },
      { "name"=>"Jean-Luc Picard", "tv_show"=>"Star Trek TNG",
        "posts"=>[
          {"title"=>"Civil rights", "content"=>"There are some words I've known since..."}
        ]
      }
    ]).run

    expect(result).to include(
      {
          "unchanged"=>0,
          "skipped"=>0,
          "replaced"=>0,
          "inserted"=>3,
          "errors"=>0,
          "deleted"=>0
      }
    )

    expect(result).to include("generated_keys")
    expect(result["generated_keys"].length).to eq(3)
  end

  describe "table query" do
    it "fetches documents" do
      cursor = r.table("authors").run
      result = cursor.to_a
      expect(result.length).to eq(3)
    end

    it "can be filtered" do
      result = r.table("authors").filter{|author| author["name"].eq("William Adama") }.run.to_a
      expect(result.last["name"]).to eq("William Adama")
      result = r.table("authors").filter{|author| author["posts"].count > 2}.run.to_a
      expect(result.last["name"]).to eq("William Adama")
    end

    it "can fetch by primary key" do
      laura = r.table("authors").run.to_a[1]
      also_laura = r.table('authors').get(laura["id"]).run
      expect(also_laura).to eq(laura)
    end
  end

  describe "updating" do
    it "can update a cursor" do
      result = r.table("authors").update({"type"=>"fictional"}).run
      expect(result).to include(
        {
          "unchanged"=>0,
          "skipped"=>0,
          "replaced"=>3,
          "inserted"=>0,
          "errors"=>0,
          "deleted"=>0
        }
      )
      results = r.table("authors").run.to_a
      expect(results.first["type"]).to eq("fictional")
    end

    it "can update a cursor with a condition" do
      result = r.table("authors").
        filter{|author| author["name"].eq("William Adama")}.
        update({"rank"=>"Admiral"}).run
      expect(result).to include(
        {
          "unchanged"=>0,
          "skipped"=>0,
          "replaced"=>1,
          "inserted"=>0,
          "errors"=>0,
          "deleted"=>0
        }
      )
      result = r.table("authors").
        filter{|author| author["name"].eq("William Adama")}.run.to_a.first
      expect(result["rank"]).to eq("Admiral")
    end

    it "can append values to arrays in records" do
      result = r.table('authors').filter{|author| author["name"].eq("Jean-Luc Picard")}.
        update{|author| {"posts"=>author["posts"].append({
            "title"=>"Shakespeare",
            "content"=>"What a piece of work is man..."})
        }}.run
      expect(result).to include(
        {
          "unchanged"=>0,
          "skipped"=>0,
          "replaced"=>1,
          "inserted"=>0,
          "errors"=>0,
          "deleted"=>0
        }
      )
      result = r.table('authors').filter{|author| author["name"].eq("Jean-Luc Picard")}.run.to_a.first
      expect(result["posts"].last["title"]).to eq("Shakespeare")
    end
  end

  describe "deleting" do
    it "works on a cursor" do
      result = r.table("authors").
        filter{ |author| author["posts"].count < 3 }.
        delete.run
      expect(result).to include ({
        "unchanged"=>0,
        "skipped"=>0,
        "replaced"=>0,
        "inserted"=>0,
        "errors"=>0,
        "deleted"=>2
      })

      result = r.table("authors").
        filter{ |author| author["posts"].count < 3 }.run.to_a
      expect(result.empty?).to be true
    end
  end

  describe 'listening to a feed' do
    it 'runs asynchronously' do
      to_take = 6 # the amount of changes we expect in the change feed
      @runnning = true
      result = []
      cursor = r.table('authors').changes.run
      iterator_thread = Thread.new do
        result += cursor.take(to_take)
      end
      producer_thread = Thread.new do
        r.table('authors').filter { |author| author['name'].eq('Jean-Luc Picard') }
          .update { |author|
            {
              'posts' => author['posts'].append(
                {
                  'title' => 'Shakespeare',
                  'content' => 'What a piece of work is man...'
                }
              )
            }
          }.run
        r.table('authors').update('type' => 'fictional').run
        r.table('authors')
         .filter { |author| author['posts'].count < 3 }
         .delete.run
      end

      waiter_thread = Thread.new do
        sleep 2
        raise 'Timeout' if @running
      end

      @running = false
      [iterator_thread, producer_thread].map(&:join)

      expect(result.length).to eq(to_take)
      result.each do |r|
        expect(r).to include('new_val')
        expect(r).to include('old_val')
      end
    end
  end
end
