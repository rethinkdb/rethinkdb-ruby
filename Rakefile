require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

PROTO_FILE_NAME = "ql2.proto"
PROTO_FILE_URL = "https://raw.githubusercontent.com/RethinkDB/rethinkdb/next/src/rdb_protocol/#{PROTO_FILE_NAME}"

PROTO_RB_FILE = "../lib/ql2.pb.rb"

desc "Downloads the latest RDB protocol protobufs and generates its API"
task :protobuf do
  mkdir_p "protobuf"
  cd "protobuf"
  `curl -o #{PROTO_FILE_NAME} #{PROTO_FILE_URL}`
  `python ../scripts/convert_protofile.py --language ruby --input-file #{PROTO_FILE_NAME} --output-file #{PROTO_RB_FILE}`
end

task :build => :protobuf
