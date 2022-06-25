#  MIT License Wikarekare.org rob@wikarekare.org
require_relative 'ping_log.rb'
require 'tmpfile'

# Extras for Wikk use.
class Graph_Ping_Log < Ping_Log
  # Class level function to draw a ping graph for the hosts services by the distribution node specified
  # @param mysql_conf [JSON] Config data used to connect to the mysql DB
  # @param dist_host [String] Distribution nodes site_name (cluster of hosts).
  # @param start_time [Time] Start of period we want to graph
  # @param end_time [Time] End of period we want to graph
  # @return [String] HTML img tag string, with an image per host graph generated
  def self.graph_clients(mysql_conf, dist_host, start_time, end_time)
    images = ''
    # Select the hosts connected to the distribution node.
    WIKK::SQL.connect(mysql_conf) do |sql|
      query = <<~SQL
        SELECT customer.site_name AS wikk
        FROM distribution, customer, customer_distribution
        WHERE distribution.site_name = '#{dist_host}'
        AND distribution.distribution_id = customer_distribution.distribution_id
        AND customer_distribution.customer_id = customer.customer_id
        ORDER BY wikk
      SQL
      sql.each_hash(query) do |row|
        ping_log = Ping_Log.new(mysql_conf)
        if (_error = ping_log.gnuplot(row['site_name'], start_time, end_time) ).nil?
          images << "<img src=\"/#{NETSTAT_DIR}/#{row['site_name']}-p5f.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\">\n"
        end
      end
    end
    return images
  end

  # Plot ping graphs.
  # First creates plot scripts for the host then calls gnuplot.
  # Scripts have embedded filename for the created graph in the 'set output' line.
  # @param host [String]
  # @param start_time [Datetime]
  # @param end_time [Datetime]
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
    rescue StandardError => e
      backtrace = error.backtrace[0].split(':')
      message = "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub(/'/, '\\\'').gsub(/\n/, ' ')}"
      return message
    end
    return nil
  end
end
