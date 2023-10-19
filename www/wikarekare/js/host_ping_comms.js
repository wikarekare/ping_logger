var wikk_host_ping = ( function() {
  var registered_local_completion = null;
  var host_ping_record = null;

  function host_ping_error(jqXHR, textStatus, errorMessage) {   //Called on failure
  }

  function host_ping_completion(data) {   //Called when everything completed, including callback.
    if(registered_local_completion != null) {
      registered_local_completion(host_ping_record);
    }
  }

  function host_ping_callback(data) {   //Called when we get a response.
    if(data != null && data.result != null) {
      host_ping_record = data.result;
    } else {
      host_ping_record = null;
    }
  }

  function get_host_ping(site_name, local_completion, delay) {
    if(delay == null) delay = 0;
    registered_local_completion = local_completion;

    var args = {
      "method": "Host_ping.read",
      "params": {
        "select_on": { "hostname": site_name },  //every active line
        "orderby": null,
        "set": null,              //blank, then no fields to update in a GET
        "result": ['hostname', 'ms'] //defaults, and ignored
      },
      "id": Date.getTime(),
      "jsonrpc": 2.0
    }

    url = "/ruby/rpc.rbx"
    wikk_ajax.delayed_ajax_post_call(url, args, host_ping_callback, host_ping_error, host_ping_completion, 'json', true, delay);
    return false;
  }

  //return a hash of key: function pairs, with the key being the same name as the function.
  //Hence call with wikk_host_ping.function_name()
  return {
    get_host_ping: get_host_ping,
    host_ping_record: host_ping_record
  };
})();
