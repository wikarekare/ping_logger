#  MIT License Wikarekare.org rob@wikarekare.org
# Individual ping record for a host and datetime.
class Ping_Record
  attr_accessor :host, :ping_times, :datetime, :failed_count, :average, :ping_max

  # initialize class with
  # @param host [String] host name we pinged (or failed to ping)
  # @param pingable [Boolean] Did we succeed in pinging this host
  # @param ping_times [Array] ping times in ms. We usually try 5 times
  # @param datetime [Time] standardized time to record against all pings in ping_times array.
  def initialize(host, pingable, ping_times, datetime )
    @datetime = datetime
    @host = host
    @pingable = pingable
    @ping_times = ping_times # Array.
    set_failed_count_and_average
    @ping_max = 0
  end

  # @return [Boolean] Host responded to pings
  def pingable?
    @pingable
  end

  # @return [String] Host responded to pings as 'T' or 'F'
  def pingable_to_s
    @pingable == true ? 'T' : 'F'
  end
  alias pingable pingable_to_s # Backward compatibility.

  # Calculate the number of failed pings and the average time of the pings
  # sets @average and @failed_count
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

  # Class level call to print a pair of dummy ping entries for gnuplot
  # Called if there was no ping data recorded for this time.
  # A record, 30 seconds before, and 29 seconds after the time is printed to cover the minute being graphed
  # @param fd [File] file descriptor of destination file
  # @param datatime [Time] time of ping
  # @param max [Integer]
  def self.print_no_data(fd, datetime, max)
    @average = 0
    # Output 2 rows, one either side of the ping, so we remove mountain peaks from line graph.
    fd.print "#{(datetime - 30).strftime('%Y-%m-%d %H:%M:%S')}\t-\t-\t-\t-\t-" # We have no ping record.
    fd.print "\t0\t0\t0\t0\t0\t#{max}\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.

    fd.print "#{(datetime + 29).strftime('%Y-%m-%d %H:%M:%S')}\t-\t-\t-\t-\t-" # We have no ping record.
    fd.print "\t0\t0\t0\t0\t0\t#{max}\t0\t#{@average}\n" # 5 0's in failure columns, no_data -> max, last 0 is a reference for graphing.
  end

  # print ping entries ready for gnuplot. Called by print_row().
  # Output changes, depending on the number of unsuccessful ping responses
  # A record, 30 seconds before, and 29 seconds after the time is printed to cover the minute being graphed
  # @param fd [File] file descriptor of destination file
  # @param datatime [Time] time of ping
  # @param max [Integer]
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

  # Use print_row_body() to output ping records for gnuplot.
  # Outputs a record 30 seconds before, and 29 seconds after the time to create line with a 1 minute period (for nicer looking graphs)
  def print_row(fd, datetime, max = 1)
    if datetime < @datetime # plot datetime has No data
      Ping_Record.print_no_data(fd, datetime, max)
      return -1
    elsif datetime == @datetime # plot datetime matches this record
      # Output 2 rows, one either side of the ping, so we remove mountain peaks from line graph.
      print_row_body(fd, datetime - 30, max) # Start of date range this ping covers.
      print_row_body(fd, datetime + 29, max) # End of date range this ping covers.
      return 0

    else # This shouldn't be able to happen. Plot time is after this record.
      Ping_Record.print_no_data(fd, datetime, max)
      return 1
    end
  end
end
