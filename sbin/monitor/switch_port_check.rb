#!/usr/local/bin/ruby
# Record host.port pingable if port is up
#
require 'snmp'
require 'time'
require 'wikk_configuration'

unless defined? WIKK_CONF
  load '/wikk/etc/wikk.conf'
end
require_relative "#{RLIB}/monitor/lastseen_sql.rb"
require_relative "#{RLIB}/utility/snmp_override.rb"

def check_switch(host_record:)
  port_operation_status = [ 'IF-MIB::ifOperStatus' ]
  port_value = []
  port_type = [ 'IF-MIB::ifType' ]

  h = host_record['hostname']
  community = host_record['community']
  begin
    hn = "#{h}.wikarekare.org"
    SNMP::Manager.open(host: hn, community: "#{community}", version: :SNMPv1, ignore_oid_order: true) do |manager|
      manager.walk(port_type) do |row|
        row.each do |vb|
          port = vb.name.to_s.split('.')[-1].to_i
          if ! port.nil?
            port_value[port] = (vb.value == 6)
          end
        end
      end
      manager.walk(port_operation_status) do |row|
        row.each do |vb|
          port = vb.name.to_s.split('.')[-1].to_i
          next unless port != nil && port_value[port]

          if vb.value == 1
            @pingable_hosts["#{h}-p#{port}"] = "#{h}-p#{port}"
          end
        end
      end
    end
  rescue StandardError => e
    warn "Check_switch(#{h}): #{e}"
    # Ignore errors
  end
end

# Should merge this into LastSeen, but will test it here
# Get just the ping records for the hosts with a specific ping time
# @param mysql_conf [Hash] DB configuration
# @param ping_time [Time] Time we are looking for
# @return hosts [Hash] key is hosts with that ping_time, value is true
def cache_online(mysql_conf:, ping_time:)
  query = <<~SQL
    SELECT hostname FROM lastping WHERE ping_time = '#{ping_time}'
  SQL
  online = {}
  WIKK::SQL.connect(mysql_conf) do |sql|
    sql.each_hash(query) do |row|
      online[row['hostname']] = true
    end
  end
  return online
end

hosts = JSON.parse(File.read(SWITCH_CHECK_PORTS))

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
@pingable_hosts = {}

t = ARGV.length == 1 ? Time.parse(ARGV[0]) : Time.now
t -= t.sec + t.usec / 1000000.0 # just want this to the minute!

# This relies on ping_logger.sh recording the host pings, before switch_port_check is run.
online = cache_online(mysql_conf: @mysql_conf, ping_time: t)

threads = []

hosts.each do |h|
  if online[h['hostname']]
    threads << Thread.new(h) { |hr| check_switch(host_record: hr) }
  end
end

threads.each(& :join)

Lastseen.record_pings(@mysql_conf, @pingable_hosts.keys, t)
