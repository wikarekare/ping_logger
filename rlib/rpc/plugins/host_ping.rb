# /usr/local/sbin/fping -C 1 -q wikk006
require 'open3'

# fping a site
class Host_ping < RPC
  def initialize(cgi:, authenticated: false)
    super
    @select_acl = [ 'hostname' ]
    @set_acl = []
    @result_acl = [ 'hostname', 'ms' ]
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|  # rubocop:disable Lint/UnusedBlockArgument
    # new record
  end

  rmethod :read do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|  # rubocop:disable Lint/UnusedBlockArgument
    select_on.each_key { |k| acceptable(field: k, acceptable_list: @select_acl) } if select_on != nil
    result.each_key { |k| acceptable(field: k, acceptable_list: @result_acl) } if result != nil
    hostname = select_on['hostname']
    raise 'Hostname required argument' if hostname.nil? || hostname == ''

    ms = '-'
    t = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    stdout_stderr, child_status = Open3.capture2e(FPING, '-C', '1', '-q', hostname)
    status = "#{FPING}: #{child_status}"

    # Fping returns results on stderr
    ms = stdout_stderr.split(':')[1].strip unless stdout_stderr.nil? || stdout_stderr == ''

    return { 'hostname' => hostname, 'ms' => ms, 'time' => t, 'child_status' => status }
  end

  rmethod :update do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|  # rubocop:disable Lint/UnusedBlockArgument
    # We don't actually do this.
  end

  rmethod :delete do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|  # rubocop:disable Lint/UnusedBlockArgument
    # We don't actually do this.
  end
end
