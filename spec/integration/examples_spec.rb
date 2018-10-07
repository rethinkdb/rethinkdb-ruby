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
end
