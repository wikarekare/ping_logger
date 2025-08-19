# Copyright Wikarekare Trust.
# BSD License.

# require "syslog"
require 'wikk_sql'
require 'time'
require 'tmpfile'

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
    @ping_max = 0
  end

  def self.graph_clients(mysql_conf, dist_host, start_time, end_time)
    images = ''
    WIKK::SQL.connect(mysql_conf) do |sql|
      query = <<~SQL
        select customer.site_name as wikk
        from distribution, customer, customer_distribution
        where distribution.site_name = '#{dist_host}'
        and distribution.distribution_id = customer_distribution.distribution_id
        and customer_distribution.customer_id = customer.customer_id
        order by wikk
      SQL
      sql.each_hash(query) do |row|
        ping_record = self.new(mysql_conf)
        if ping_record.gnuplot(row['site_name'], start_time, end_time).nil?
          images << "<img src=\"/#{NETSTAT_DIR}/#{row['site_name']}-p5f.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\">\n"
        end
      end
    end
    return images
  end

  def gnuplot(host, start_time, end_time)
    start_time -= start_time.sec + start_time.usec / 1000000.0
    end_time -= end_time.sec + end_time.usec / 1000000.0
    begin
      temp_filename_txt = "#{TMP_PLOT_DIR}/#{host}-pings.txt"
      temp_filename_plot = "#{TMP_PLOT_DIR}/#{host}-pings.plot"

      TmpFileMod::TmpFile.open(temp_filename_plot, 'w') do |plot_fd|
        plot_fd.no_unlink
        TmpFileMod::TmpFile.open(temp_filename_txt, 'w') do |txt_fd|
          txt_fd.no_unlink
          txt_fd.puts "# #{host} #{start_time.strftime('%Y-%m-%d %H:%M:%S')} #{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
          @ping_max, @ping_records = get_hosts_pings(host, start_time, end_time) # sets up the ping records from DB records.
          t = start_time
          i = 0
          while t <= end_time
            if i < @ping_records.length
              case @ping_records[i].print_row(txt_fd, t, @ping_max)
              when 0 # this is the same datetime
                i += 1 # move onto next record and increment the time
                t += 60 # increment by a minute
              when 1   # 1 => t >, which can happen if there are two identical ping records!
                # move to the next record, but us the same time (i.e. try to catch up)
                i += 1 # move onto next record
              when -1	# -1 => t < record datetime
                # Stay on this record, but increment the time.
                t += 60 # increment by a minute
              end
            else # we ran out of records to print, so are filling in with empty ones.
              Ping_Record.print_no_data(txt_fd, t, @ping_max)
              t += 60 # increment by a minute
            end
          end

          txt_fd.flush  # ensure disk copy has been written.

          plot_fd.print <<~EOF
            set terminal png truecolor size 450,200 small
            set title 'Ping response in ms from #{host}'
            set nokey
            set timefmt "%Y-%m-%d %H:%M:%S"
            set datafile separator '\\t'
            set xdata time
            set format x "%H:%M\\n%m/%d"
            #set xlabel 'Time'
            set xtics border out nomirror autofreq
            set xrange ["#{start_time.strftime('%Y-%m-%d %H:%M:%S')}":"#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"]
            set ylabel 'Pings ms'
            set yrange [0:#{@ping_max}]
            set output '#{WWW_DIR}/#{NETSTAT_DIR}/#{host}-p5f.png'
            set datafile missing '-'
            plot "#{temp_filename_txt}" u 1:7:13 w filledcu lc rgbcolor "#ccffff", "" u 1:8:13 w filledcu lc rgbcolor "#99ffff", "" u 1:9:13 w filledcu lc rgbcolor "#4dffff", "" u 1:10:13 w filledcu lc rgbcolor "#00ffff", "" u 1:2:3 w filledcu lc rgbcolor "#eceeff", "" u 1:3:4 w filledcu lc rgbcolor "#ccccff", "" u 1:4:5 w filledcu lc rgbcolor "#ccccff", ""  u 1:5:6 w filledcu lc rgbcolor "#eceeff", "" u 1:4 w lines lc rgbcolor "#000000", "" u 1:14 w lines lc rgbcolor "#00ff00", "" u 1:11:13 w filledcu lc rgbcolor "#ff4455", "" u 1:13:12 w filledcu lc rgbcolor "#ffff88"
          EOF

          plot_fd.flush  # ensure disk copy has been written.

          TmpFileMod::TmpFile.exec(GNUPLOT, temp_filename_plot )
        end
      end
    rescue Exception => e # rubocop:disable Lint/RescueException -- We don't want cgi's crashing without producing output
      backtrace = e.backtrace[0].split(':')
      message = "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub('\'', '\\\'').gsub("\n", ' ')}"
      return message
    end
    return nil
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
      rescue StandardError => _e
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
  def get_hosts_pings(host, start_time, end_time)
    ping_records = []
    ping_max = 1 # minimum value for longest ping, even if max ping response is less. Used for graph generation, to have a minimum y axis max value.
    WIKK::SQL.connect(@mysql_conf) do |sql|
      sql.transaction do # doing this to ensure we have a consistent state in the Round Robin indexes.
        query = <<~SQL
          SELECT ping_time, ping, time1, time2, time3, time4, time5
          FROM pinglog
          WHERE host_name = '#{host}'
          AND ping_time >= '#{start_time.strftime('%Y-%m-%d %H:%M:%S')}'
          AND ping_time <= '#{end_time.strftime('%Y-%m-%d %H:%M:%S')}'
          ORDER BY ping_time
        SQL
        sql.each_row(query) do |row| # Array returned.
          begin
            times = row[2..6].collect(&:to_f)
            tm = row[0].is_a?( String ) ? Time.parse(row[0]) : row[0]
            ping_records << Ping_Record.new(host, row[1] == 'T', times, tm )
            times.each { |r| ping_max = r if r > ping_max } # update the maximum ping response value, for graph y axis use.
          rescue StandardError => _e
            # Ignore errors for this host and continue to the next one.
          end
        end
      end
    end
    return ping_max, ping_records # Longest ping, Array of Ping_Records.
  end

  # Call get_hosts_pings without needing a Ping_Log instance
  def self.get_hosts_pings(mysql_conf, host, start_time, end_time)
    pl = self.new(mysql_conf)
    return pl.get_host_pings(host, start_time, end_time)
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
    WIKK::SQL.connect(@mysql_conf) do |sql|
      sql.transaction do
        res = sql.query_hash <<~SQL
          SELECT sequence_nextval('ping_log.ping_id') AS seq
        SQL
        @ping_id = res.first['seq'].to_i

        if @ping_records.length > 0
          sql.query <<~SQL
            DELETE FROM pinglog WHERE ping_id = #{@ping_id}
          SQL
          sql.query <<~SQL
            INSERT INTO pinglog (ping_id, ping_time, host_name, ping, time1, time2, time3, time4, time5)
            VALUES #{sql_ping_values(@ping_id)}
          SQL
        end
      end
    end
  end

  private def sql_ping_values(ping_id)
    return '' if @ping_records.length == 0

    pr = @ping_records[0]
    value_str = "(#{ping_id}, '#{@datetime.strftime('%Y-%m-%d %H:%M:%S')}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"

    @ping_records[1..-1].each do |pr| # rubocop:disable Lint/ShadowingOuterLocalVariable
      value_str << ", (#{ping_id}, '#{@datetime.strftime('%Y-%m-%d %H:%M:%S')}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"
    end

    return value_str
  end
end
