require 'syslog'
require 'rubygems'
require 'mysql'
require_relative 'lastseen_sql.rb'
require 'tmpfile'
require 'time'

class Ping_Record
  attr_accessor :host, :ping_times, :datetime, :failed_count, :average

  def initialize(host, pingable, ping_times, datetime )
    @host = host
    @pingable = pingable
    @ping_times = ping_times # Array.
    set_failed_count_and_average
    @datetime = datetime
    @ping_max = 0
  end

  def pingable?
    @pingable
  end

  def pingable_to_s
    @pingable == true ? 'T' : 'F'
  end
  alias pingable pingable_to_s # Backward compatibility.

  def set_failed_count_and_average
    @failed_count = 0
    sum = count = 0
    @ping_times.each do |t|
      if t == -1
        @failed_count += 1
      else
        sum += t
        count += 1
      end
    end

    @average = if count > 0
                 sum / count
               else
                 0
               end
  end

  def self.print_no_data(fd, datetime, max)
    @average = 0
    # Output 2 rows, one either side of the ping, so we remove mountain peaks from line graph.
    fd.print "#{(datetime - 30).strftime('%Y-%m-%d %H:%M:%S')}\t-\t-\t-\t-\t-" # We have no ping record.
    fd.print "\t0\t0\t0\t0\t0\t#{max}\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.

    fd.print "#{(datetime + 29).strftime('%Y-%m-%d %H:%M:%S')}\t-\t-\t-\t-\t-" # We have no ping record.
    fd.print "\t0\t0\t0\t0\t0\t#{max}\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
  end

  def print_row_body(fd, datetime, max)
    case @failed_count
    when 0 # Got All pings
      fd.print "#{datetime.strftime('%Y-%m-%d %H:%M:%S')}\t#{@ping_times[0]}\t#{@ping_times[1]}\t#{@ping_times[2]}\t#{@ping_times[3]}\t#{@ping_times[4]}"
      fd.print "\t0\t0\t0\t0\t0\t0\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
    when 1 # Lost 1
      fd.print "#{datetime.strftime('%Y-%m-%d %H:%M:%S')}\t#{@ping_times[1]}\t#{@ping_times[2]}\t#{(@ping_times[2] + @ping_times[3]) / 2}\t#{@ping_times[3]}\t#{@ping_times[4]}"
      fd.print "\t#{max}\t0\t0\t0\t0\t0\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
    when 2
      fd.print "#{datetime.strftime('%Y-%m-%d %H:%M:%S')}\t#{@ping_times[2]}\t#{@ping_times[2]}\t#{@ping_times[3]}\t#{@ping_times[4]}\t#{@ping_times[4]}"
      fd.print "\t0\t#{max}\t0\t0\t0\t0\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
    when 3
      fd.print "#{datetime.strftime('%Y-%m-%d %H:%M:%S')}\t#{@ping_times[3]}\t#{@ping_times[3]}\t#{(@ping_times[3] + @ping_times[4]) / 2}\t#{@ping_times[4]}\t#{@ping_times[4]}"
      fd.print "\t0\t0\t#{max}\t0\t0\t#0\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
    when 4
      fd.print "#{datetime.strftime('%Y-%m-%d %H:%M:%S')}\t#{@ping_times[4]}\t#{@ping_times[4]}\t#{@ping_times[4]}\t#{@ping_times[4]}\t#{@ping_times[4]}"
      fd.print "\t0\t0\t0\t#{max}\t0\t0\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
    when 5 # Lost all pings.
      fd.print "#{datetime.strftime('%Y-%m-%d %H:%M:%S')}\t-\t-\t-\t-\t-"
      fd.print "\t0\t0\t0\t0\t#{max}"
      fd.print "\t0\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
    end
  end

  def print_row(fd, datetime, max = 1)
    if datetime < @datetime
      Ping_Record.print_no_data(fd, datetime, max)
      return -1
    elsif datetime == @datetime
      # Output 2 rows, one either side of the ping, so we remove mountain peaks from line graph.
      print_row_body(fd, datetime - 30, max) # Start of date range this ping covers.
      print_row_body(fd, datetime + 29, max) # End of date range this ping covers.
      return 0

    else # This shouldn't be able to happen.
      Ping_Record.print_no_data(fd, datetime, max)
      return 1
    end
  end
end

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
    if (my = Mysql.new(mysql_conf.host, mysql_conf.dbuser, mysql_conf.key, mysql_conf.db)) != nil
      res = my.query('select customer.site_name as wikk from distribution, customer, customer_distribution ' +
                     " where distribution.site_name = '#{dist_host}' and distribution.distribution_id = customer_distribution.distribution_id " +
                     ' and customer_distribution.customer_id = customer.customer_id order by wikk'
                    )
      if res != nil
        res.each do |row|
          ping_record = Ping.new(mysql_conf)
          if (error = ping_record.gnuplot(row[0], start_time, end_time) ).nil?
            images << "<img src=\"/#{NETSTAT_DIR}/#{row[0]}-p5f.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\">\n"
          end
        end
        res.free
      end
      my.close
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
      rescue Exception => e
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

    pr = @ping_records[0]
    value_str = "(#{ping_id}, '#{@datetime_str}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"

    @ping_records[1..-1].each do |pr|
      value_str << ", (#{ping_id}, '#{@datetime_str}', '#{pr.host}', '#{pr.pingable_to_s}', #{pr.ping_times[0]}, #{pr.ping_times[1]}, #{pr.ping_times[2]}, #{pr.ping_times[3]}, #{pr.ping_times[4]})"
    end

    return value_str
  end

  def sql_record_of_ping_results
    begin
      if (my = Mysql.new(@mysql_conf.host, @mysql_conf.dbuser, @mysql_conf.key, @mysql_conf.db)) != nil
        # puts my.class
        # p @mysql_conf
        my.query('START TRANSACTION WITH CONSISTENT SNAPSHOT')  # Replace with transaction block.
        if @ping_records.length > 0
          my.query("SELECT sequence_nextval('ping_log.ping_id')") do |res|
            res.each do |row|
              @ping_id = row[0].to_i
            end
          end

          my.query("UPDATE ping_index  SET ping_id = #{@ping_id}, last_ping = '#{@datetime_str}'")
          my.query("DELETE FROM pinglog  WHERE ping_id = #{@ping_id}")
          my.query("INSERT INTO pinglog (ping_id, ping_time, host_name, ping, time1, time2, time3, time4, time5) VALUES #{sql_ping_values(@ping_id)}")
        end
        my.query('COMMIT')
      end
    rescue Exception => e
      if my != nil
        my.query('ROLLBACK')
        # @log.err("#{time} :  #{error}")
      end
      puts e
    ensure
      if my != nil
        my.close
      end
    end
  end

  def get_hosts_pings(host, start_time, end_time)
    begin
      if (my = Mysql.new(@mysql_conf.host, @mysql_conf.dbuser, @mysql_conf.key, @mysql_conf.db)) != nil

        my.query('START TRANSACTION WITH CONSISTENT SNAPSHOT')

        @ping_max = 1 # default graph would then be y [0..15], even if max ping response is less
        @ping_records = []

        # Fetch the ping records from the DB and process them.
        my.query("select  ping_time, ping, time1, time2, time3, time4, time5 from pinglog where host_name = '#{host}' and ping_time >= '#{start_time.strftime('%Y-%m-%d %H:%M:%S')}' and ping_time <= '#{end_time.strftime('%Y-%m-%d %H:%M:%S')}' order by ping_time") do |res|
          res.each do |row|
            begin
              times = row[2..6].collect { |x| x.to_f }
              @ping_records << Ping_Record.new(host, row[1] == 'T', times, Time.parse(row[0]) )
              times.each { |r| @ping_max = r if r > @ping_max }
            rescue Exception => e
            end
          end
        end

        my.query('COMMIT')
      end
    rescue Exception => e
      my.query('ROLLBACK') if my != nil
      # @log.err("#{Time.now} :  #{error}")
    ensure
      if my != nil
        my.close
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
    rescue Exception => e
      backtrace = error.backtrace[0].split(':')
      message = "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub(/'/, '\\\'').gsub(/\n/, ' ')}"
      return message
    end
    return nil
  end
end
