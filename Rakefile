require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

PROTO_FILE_NAME = "ql2.proto"
PROTO_FILE_URL = "https://raw.githubusercontent.com/RebirthDB/rebirthdb/next/src/rdb_protocol/#{PROTO_FILE_NAME}"
FILE_CONVERTER_NAME = "convert_protofile.py"
FILE_CONVERTER_URL = "https://raw.githubusercontent.com/RebirthDB/rebirthdb/next/scripts/#{FILE_CONVERTER_NAME}"

PROTO_RB_FILE = "../lib/ql2.pb.rb"

task :protobuf do
  mkdir_p "protobuf"
  cd "protobuf"
  `curl -o #{PROTO_FILE_NAME} #{PROTO_FILE_URL}`
  `curl -o #{FILE_CONVERTER_NAME} #{FILE_CONVERTER_URL}`
  `python #{FILE_CONVERTER_NAME} --language ruby --input-file #{PROTO_FILE_NAME} --output-file #{PROTO_RB_FILE}`
end

task :build => :protobuf
