#  MIT License Wikarekare.org rob@wikarekare.org
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
      query = <<~SQL
        SELECT concat(distribution.site_name,' clients') AS hostgroup, customer.site_name
        FROM distribution LEFT JOIN customer_distribution USING (distribution_id)
        LEFT JOIN customer USING (customer_id)
        WHERE distribution.active = 1
        ORDER BY distribution.site_name, customer.site_name
      SQL
      sql.each_hash(query) do |row|
        if @clusters[row['hostgroup'].capitalize].nil?
          @clusters[row['hostgroup'].capitalize] = [ row['site_name'] ] # new cluster, so create within an array
        elsif row[1] != nil
          @clusters[row['hostgroup'].capitalize] << row['site_name']
        end
      end
    end
  end
end
