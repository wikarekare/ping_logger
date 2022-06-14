#!/usr/local/bin/ruby
load '/wikk/etc/wikk.conf'
require 'wikk_sql'
require 'wikk_configuration'
require 'fileutils'

# This generates a file with a host, we wish to ping, per line.
# This file get used by fping, as part of our site monitoring.

# Sets up empty @ignore_hosts hash
# and empty array of hosts to ping
def setup
  @ignore_hosts = {}
  @host_list = []
end

# Does a DB query to build a list host interface names for customers sites, towers, and backbone routers.
def fetch_host_list
  query = <<~SQL
    SELECT site_name FROM customer WHERE active = 1 UNION
    SELECT CONCAT(site_name,\'-wifi\') AS site_name FROM backbone WHERE active=1 UNION
    SELECT site_name FROM backbone WHERE active=1 UNION
    SELECT CONCAT(site_name,\'-wifi\') AS site_name FROM distribution WHERE active=1  UNION
    SELECT site_name FROM distribution WHERE active=1
    ORDER BY site_name
  SQL

  @mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
  WIKK::SQL.connect(@mysql_conf) do |sql|
    sql.each_hash(query) do |row|
      host_name = row['site_name']
      if @ignore_hosts[host_name].nil?
        @host_list << host_name
        @ignore_hosts[host_name] = true
      end
    end
  end
end

# Reads a file to get a list of hosts we don't want to monitor.
# These include some of the automatically generated names from the DB,
# as not all correspond to an actual host interface
def load_ignore_hosts
  File.open(FPING_IGNORE, 'r') do |fd|
    fd.each_line do |l|
      @ignore_hosts[l.chomp.strip] = true
    end
  end
end

# Reads a file to suppliment the host interface names we get from the database
def load_extra_hosts
  File.open(FPING_EXTRA, 'r') do |fd|
    fd.each_line do |l|
      host_name = l.chomp.strip
      if @ignore_hosts[host_name].nil?
        @host_list << host_name
        @ignore_hosts[host_name] = true
      end
    end
  end
end

# Create a temporary file from the host list, then
# move it to the config file location.
def gen_fping_file
  File.open('/tmp/fping_hosts', 'w+') do |fd|
    @host_list.sort.each do |h|
      fd.puts h
    end
  end

  FileUtils.mv('/tmp/fping_hosts', FPING_HOSTS) if @host_list.length > 0
end

setup
load_ignore_hosts
load_extra_hosts
fetch_host_list
gen_fping_file
