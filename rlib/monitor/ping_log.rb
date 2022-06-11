# Copyright Wikarekare Trust.
# BSD License.

# require "syslog"
require 'wikk_sql'
require 'time'

require_relative 'ping_record.rb'
require_relative 'lastseen_sql.rb'

# Holds a point in time record of ping times to a set of hosts.
# i.e. we ping all these host with fping, and want to record their individual ping times for this run of fping.
class Ping_Log
  attr_accessor :hosts, :datetime

  # init Ping_Log class
  # @param db_conf [Hash] DB connection details
  # @param datetime [Time] this set of ping records will be recorded against this timestamp.
  def initialize(db_conf, datetime = nil)
    @mysql_conf = db_conf
    # @log = Syslog.open("ping_log")

    # If we aren't given a datetime to use, then assume this is now.
    @datetime = if datetime.nil?
                  Time.now
                else
                  datetime # We are associating all pings with this time.
                end
    # Truncate to the nearest minute by subtracting the seconds and microseconds
    @datetime -= @datetime.sec + @datetime.usec / 1000000.0

    @pingable_hosts = [] # Array of hostname we could ping.
    @ping_records = [] # Array of all ping results.
  end

  # print date time and a tab separated list of hosts that we received a ping response from.
  def to_s
    "datetime\t#{@pingable_hosts.join("\t")}"
  end

  # save the ping entries to the database
  # and update the lastseen record for the host.
  # The Lastseen table is used as a quick way to find when we could last ping a host.
  # Lastseen may also be the only record we have, as the ping records are aged out to save space.
  def save
    # Want to update the last seen record, which persists for all time.
    Lastseen.record_pings(@mysql_conf, @pingable_hosts, @datetime) # Just a summary of the hosts that responded.
    # Record the ping records, which go into a round robin table, so will eventually get overwritten.
    sql_record_of_ping_results # ALL the results
  end

  # Parse fping output from a ""
  # @param [String] Text output from "fping -C 5 -q -f hostfile"
  def parse(source)
    source.each_line do |line|
      begin
        # Lines of form   "wikk004 : 104.42 432.26 148.44 150.59 2.53"
        # And of the form "wikk054 : - - - - -" when host not online.
        words = line.strip.squeeze(' \t').split(/[ \t]/)
        if words && words[0] != 'ICMP' && words[1] == ':' # Lines that have ping responses have : there.
          update_pingrecord(words[0], words[2, 6]) # Add this ping record.
        end
      rescue Exception => e
        # @log.err("#{datetime} : #{words.join(',')} " + error)
      end
    end
  end

  # Buggered if I know why I wrote this.
  def clean_ping_time(v)
    return -1 if v.nil? || v.to_s == ''

    return v.to_s
  end

  # Get previously saved set of ping records for a host.
  # @param host [String] host we want ping records for
  # @param start_time [Time] want records from, and including this time
  # @param end_time [Time] want records up to, and including this time
  # @return [ping_max, Array] Longest ping, Array of Ping_Records.
  def self.get_hosts_pings(mysql_conf, host, start_time, end_time)
    ping_records = []
    WIKK::SQL.connect(mysql_conf) do |sql|
      sql.transaction do # doing this to ensure we have a consistent state in the Round Robin indexes.
        ping_max = 1 # minimum value for longest ping, even if max ping response is less. Used for graph generation, to have a minimum y axis max value.
        sql.each_row("select  ping_time, ping, time1, time2, time3, time4, time5 from pinglog where host_name = '#{host}' and ping_time >= '#{start_time.strftime('%Y-%m-%d %H:%M:%S')}' and ping_time <= '#{end_time.strftime('%Y-%m-%d %H:%M:%S')}' order by ping_time") do |row|
          begin
            times = row[2..6].collect { |x| x.to_f }
            ping_records << Ping_Record.new(host, row[1] == 'T', times, Time.parse(row[0]) )
            times.each { |r| ping_max = r if r > ping_max } # update the maximum ping response value, for graph y axis use.
          rescue Exception => e
          end
        end
      end
    end
    return ping_max, ping_records # Longest ping, Array of Ping_Records.
  end

  # Record a parsed fping line. (parsed by parse())
  # @param host [String] host name for this ping record
  # @param values [Array] ping return values for this host
  private def update_pingrecord(host, values)
    failed = 0 # Count of pings that failed.

    values.collect! do |v|
      if v == '-' # update ping value to be -1, if entry is '-'
        failed += 1
        -1.0 # helps with the sort and is out of range retrieving the data.
      else
        v.to_f # update array entry class, converting string to float.
      end
    end

    values.sort! # Sorting ping values Helps with graphing if they are in lowest to highest order
    @ping_records << Ping_Record.new(host, failed != values.length, values, @datetime) # Result record for this host.
    @pingable_hosts << host if failed != values.length # we got at least one response.
  end

  # Save the record to the SQL DB
  private def sql_record_of_ping_results
    WIKK::SQL.connect(@mysql_conf) do |my|
      my.transaction do
        my.query("select sequence_nextval('ping_log.ping_id')") do |res|
          res.each do |row|
            @ping_id = row[0].to_i
          end
        end

        if @ping_records.length > 0
          my.query("delete from pinglog  where ping_id = #{@ping_id}")
          my.query('insert into pinglog (ping_id, ping_time, host_name, ping, time1, time2, time3, time4, time5) values ' + sql_ping_values(@ping_id) )
        end
      end
    end
  end

  private def sql_ping_values(ping_id)
    return '' if @ping_records.length == 0

    pr = @ping_records[0]
    value_str = "(#{ping_id}, '#{@datetime.strftime('%Y-%m-%d %H:%M:%S')}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"

    @ping_records[1..-1].each do |pr|
      value_str << ", (#{ping_id}, '#{@datetime.strftime('%Y-%m-%d %H:%M:%S')}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"
    end

    return value_str
  end
end
