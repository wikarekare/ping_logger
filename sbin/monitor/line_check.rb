#!/usr/local/bin/ruby
# Record line state as if we pinged them
# Actually uses snmp query, done on the Master gate node.
# The result of which is copied to the web server dir
# #{LINE_WWW_DIR}/line_active.json
# require 'snmp'
require 'time'
require 'wikk_configuration'

load '/wikk/etc/wikk.conf' unless defined? WIKK_CONF
require_relative "#{RLIB}/monitor/lastseen_sql.rb"

def load_current_line_state(timestamp:)
  lines = []
  active_lines = JSON.parse(File.read("#{LINE_WWW_DIR}/line_active.json"))
  active_lines.each_with_index do |active, i|
    next unless active

    lines << "line#{i}"
  end
  Lastseen.record_pings(@mysql_conf, lines, timestamp)
end

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

t = ARGV.length == 1 ? Time.parse(ARGV[0]) : Time.now
t -= t.sec + t.usec / 1000000.0 # just want this to the minute!
load_current_line_state(timestamp: t)
