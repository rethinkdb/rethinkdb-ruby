module RethinkDB::IntegrationHelpers
  INTEGRATION_TEST_DB = 'integration_test'

  def conn
    @conn ||= r.connect(host: ENV['RETHINKDB_HOST'] || 'localhost')
  end

  def db
    r.db(INTEGRATION_TEST_DB)
  end

  def integration_setup
    if r.db_list.run(conn).include? INTEGRATION_TEST_DB
      r.db_drop(INTEGRATION_TEST_DB).run(conn)
    end

    r.db_create(INTEGRATION_TEST_DB).run(conn)

    conn.use(INTEGRATION_TEST_DB)
    conn.repl
  end

  def integration_teardown
    r.db_drop(INTEGRATION_TEST_DB).run(conn)
    conn.close
    @conn = nil
  end
end
