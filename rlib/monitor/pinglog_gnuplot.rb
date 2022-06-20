require 'syslog'
require 'rubygems'
require 'mysql'
require 'tmpfile'
require 'time'
require_relative 'lastseen_sql.rb'
require_relative 'ping_record.rb'

# Retired Gnuplot version of Ping.
class Ping
  attr_accessor :hosts, :datetime

  def initialize(db_conf, datetime = nil)
    @mysql_conf = db_conf
    # @log = Syslog.open("ping_log")

    @datetime = if datetime.nil?
                  Time.now
                else
                  datetime # We are associating all pings with this time.
                end
    @datetime -= @datetime.sec + @datetime.usec / 1000000.0
    @datetime_str = @datetime.strftime('%Y-%m-%d %H:%M:%S')

    @pingable_hosts = [] # Array of hostname we could ping.
    @ping_records = [] # Array of all ping results.
  end

  def self.graph_clients(mysql_conf, dist_host, start_time, end_time)
    images = ''
    WIKK::SQL.connect(@mysql_conf) do |sql|
      query = <<~SQL
        SELECT customer.site_name AS wikk
        FROM distribution, customer, customer_distribution
        WHERE distribution.site_name = '#{dist_host}'
        AND distribution.distribution_id = customer_distribution.distribution_id
        AND customer_distribution.customer_id = customer.customer_id
        ORDER BY wikk
      SQL
      sql.each_hash(query) do |row|
        ping_record = Ping.new(mysql_conf)
        if ping_record.gnuplot(row['site_name'], start_time, end_time).nil?
          images << "<img src=\"/#{NETSTAT_DIR}/#{row[0]}-p5f.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\">\n"
        end
      end
    end
    return images
  end

  # print date time and hosts we received ping responses from.
  def to_s
    "datetime\t#{@pingable_hosts.join("\t")}"
  end

  # save to the database
  def save
    Lastseen.record_pings(@mysql_conf, @pingable_hosts, @datetime) # Just a summary of the hosts that responded.
    sql_record_of_ping_results # ALL the results
  end

  # Parse output from a "fping -C 5 -q -f hostfile"
  # Lines of form "wikk004 : 104.42 432.26 148.44 150.59 2.53"
  # And "wikk054 : - - - - -" when host not online.
  def parse(_time, source)
    source.each_line do |line|
      begin
        words = line.strip.squeeze(' \t').split(/[ \t]/)
        if words && words[0] != 'ICMP' && words[1] == ':' # Lines that have ping responses have : there.
          update_pingrecord(words[0], words[2, 6])
        end
      rescue StandardError => e
        # @log.err("#{time} : #{words.join(',')} " + error)
      end
    end
  end

  def update_pingrecord(host, values)
    failed = 0

    values.collect! do |v|
      if v == '-'
        failed += 1
        -1.0 # helps with the sort and is out of range retrieving the data.
      else
        v.to_f
      end
    end

    # Sorting values Helps with graphing if they are in lowest to highest order
    values.sort!
    @ping_records << Ping_Record.new(host, failed != values.length, values, @datetime) # Result record for this host.
    @pingable_hosts << host if failed != values.length
  end

  def clean_ping_time(v)
    return -1 if v.nil? || v.to_s == ''

    return v.to_s
  end

  def sql_ping_values(ping_id)
    return '' if @ping_records.length == 0

    pr1 = @ping_records[0]
    value_str = "(#{ping_id}, '#{@datetime_str}', '#{pr1.host}', '#{pr1.pingable_to_s}', #{pr1.ping_times[0]}, #{pr1.ping_times[1]}, #{pr1.ping_times[2]}, #{pr1.ping_times[3]}, #{pr1.ping_times[4]})"

    @ping_records[1..-1].each do |pr|
      value_str << ", (#{ping_id}, '#{@datetime_str}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"
    end

    return value_str
  end

  def sql_record_of_ping_results
    WIKK::SQL.connect(@mysql_conf) do |sql|
      sql.transaction do # doing this to ensure we have a consistent state in the Round Robin indexes.
        if @ping_records.length > 0
          query = <<~SQL
            SELECT sequence_nextval('ping_log.ping_id') AS seq
          SQL
          sql.each_hash(query) do |row|
            @ping_id = row['seq'].to_i
          end

          sql.query <<~SQL
            UPDATE ping_index SET ping_id = #{@ping_id}, last_ping = '#{@datetime_str}'"
          SQL
          sql.query <<~SQL
            DELETE FROM pinglog WHERE ping_id = #{@ping_id}"
          SQL
          sql.query <<~SQL
            INSERT INTO pinglog (ping_id, ping_time, host_name, ping, time1, time2, time3, time4, time5)
            VALUES #{sql_ping_values(@ping_id)}"
          SQL
        end
      end
    end
  end

  def get_hosts_pings(host, start_time, end_time)
    WIKK::SQL.connect(@mysql_conf) do |sql|
      @ping_max = 1 # default graph would then be y [0..15], even if max ping response is less
      @ping_records = []

      # Fetch the ping records from the DB and process them.
      query = <<~SQL
        SELECT  ping_time, ping, time1, time2, time3, time4, time5
        FROM pinglog
        WHERE host_name = '#{host}'
        AND ping_time >= '#{start_time.strftime('%Y-%m-%d %H:%M:%S')}'
        AND ping_time <= '#{end_time.strftime('%Y-%m-%d %H:%M:%S')}'
        ORDER BY ping_time
      SQL
      sql.each_row(query) do |row| # Array return
        begin
          times = row[2..6].collect(& :to_f )
          tm = row[0].is_a?( String ) ? Time.parse(row[0]) : row[0]
          @ping_records << Ping_Record.new(host, row[1] == 'T', times, tm )
          times.each { |r| @ping_max = r if r > @ping_max }
        rescue StandardError => _e
          # Ignore individual host errors
        end
      end
    end
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
          get_hosts_pings(host, start_time, end_time) # sets up the ping records from DB records.
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
              when -1	#-1 => t < record datetime
                # Stay on this record, but increment the time.
                t += 60 # increment by a minute
              end
            else # we ran out of records to print, so are filling in with empty ones.
              Ping_Record.print_no_data(txt_fd, t, @ping_max)
              t += 60 # increment by a minute
            end
          end

          txt_fd.flush  # ensure disk copy has been written.

          plot_fd.print <<-EOF
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
    rescue StandardError => e
      backtrace = error.backtrace[0].split(':')
      message = "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub(/'/, '\\\'').gsub(/\n/, ' ')}"
      return message
    end
    return nil
  end
end
