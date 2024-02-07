#!/usr/local/bin/ruby
# from: fping -c 5 -q -f filename
# Producing: wikk021               : xmt/rcv/%loss = 5/5/0%, min/avg/max = 3.53/4.97/7.26
#
CONF_FILE = "#{ARGV[0]}"

require 'wikk_configuration'
unless defined? WIKK_CONF
  load '/wikk/etc/wikk.conf'
end
require_relative "#{RLIB}/monitor/ping_log.rb"

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

t = ARGV.length == 2 ? Time.parse(ARGV[1]) : Time.now
t = (t - t.sec) # just want this to the minute!
pings_state = Ping_Log.new(@mysql_conf, t)
pings_state.parse($stdin)
pings_state.save
