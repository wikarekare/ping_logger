#!/usr/local/bin/ruby
# Record host.port pingable if port is up
#
require 'snmp'
require 'time'
require 'wikk_configuration'
RLIB = '/wikk/rlib'
require_relative "#{RLIB}/wikk_conf.rb"
require_relative "#{RLIB}/rlib/monitor/lastseen_sql.rb"
require_relative "#{RLIB}/rlib/utility/snmp_override.rb"

port_operation_status = [ 'IF-MIB::ifOperStatus' ]
port_type = [ 'IF-MIB::ifType' ]

host = JSON.parse(File.read(SWITCH_CHECK_PORTS))

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
@pingable_hosts = []
@port_type = []

t = ARGV.length == 1 ? Time.parse(ARGV[0]) : Time.now
t -= t.sec + t.usec / 1000000.0 # just want this to the minute!

host.each do |host_record|
  h = host_record['hostname']
  community = host_record['community']
  begin
    hn = "#{h}.wikarekare.org"
    SNMP::Manager.open(host: hn, community: "#{community}", version: :SNMPv1, ignore_oid_order: true) do |manager|
      manager.walk(port_type) do |row|
        row.each do |vb|
          port = vb.name.to_s.split('.')[-1].to_i
          if ! port.nil?
            @port_type[port] = (vb.value == 6)
          end
        end
      end
      manager.walk(port_operation_status) do |row|
        row.each do |vb|
          port = vb.name.to_s.split('.')[-1].to_i
          next unless port != nil && @port_type[port]

          if vb.value == 1
            @pingable_hosts << "#{h}-p#{port}"
          end
        end
      end
    end
  rescue StandardError => _e
    # Ignore errors
  end
end

# p @pingable_hosts
Lastseen.record_pings(@mysql_conf, @pingable_hosts, t)
