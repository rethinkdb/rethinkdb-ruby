describe "the docs examples" do
  it "can create and drop a table" do
    result = db.table_create('dc_universe').run(conn)
    expect(result).to include({"tables_created" => 1})
    result = db.table_drop('dc_universe').run(conn)
    expect(result).to include({"tables_dropped" => 1})
  end
end
