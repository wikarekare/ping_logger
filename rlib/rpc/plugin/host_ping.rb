# /usr/local/sbin/fping -C 1 -q wikk006
require 'open3'

class Host_ping < RPC
  def initialize(authenticated = false)
    super(authenticated)
    @select_acl = [ 'hostname' ]
    @set_acl = []
    @result_acl = [ 'hostname', 'ms' ]
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # new record
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    select_on.each { |k, _v| acceptable(field: k, acceptable_list: @select_acl) } if select_on != nil
    result.each { |k, _v| acceptable(field: k, acceptable_list: @result_acl) } if result != nil
    hostname = select_on['hostname']
    raise 'Hostname required argument' if hostname.nil? || hostname == ''

    ms = '-'
    t = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    stderr_result, stdin_result = Open3.capture2e(FPING, '-C', '1', '-q', hostname)

    # Fping returns results on stderr
    ms = stderr_result.split(':')[1].strip if stderr_result != nil && stderr_result != ''

    return { 'hostname' => hostname, 'ms' => ms, 'time' => t }
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end
end
