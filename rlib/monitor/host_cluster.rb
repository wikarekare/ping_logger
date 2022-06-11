# Group of hosts we want to report on as a unit.
# In the Wikarekare system, this is defined by a distribution site name.
# Distribution sites are wifi routers, that each client's wifi basestation connect to.
class Host_Cluster
  attr_reader :clusters

  # Initialize the class, fetching the DB
  # @param db_conf [Hash] DB connection details
  def initialize(db_conf)
    @mysql_conf = db_conf
    get_cluster_data
  end

  # For graphing, we want to know the status of groups of hosts (clusters).
  # In Wikarekare, these are client sites connecting through a common distribution site
  def get_cluster_data
    WIKK::SQL.connect(@mysql_conf) do |sql|
      # get the list of distribution sites and the clients site names that connect through them.
      sql.each_row('select hostgroup_name, host_name from hostgroup left join host using (host_id) where host.active = 1') do |row|
        if @clusters[row[0].capitalize].nil?
          @clusters[row[0].capitalize] = [ row[1]] # new cluster, so create within an array
        elsif row[1] != nil
          @clusters[row[0].capitalize] << row[1]
        end
      end
    end
  end
end
