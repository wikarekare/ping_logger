var wikk_last_seen = ( function() {
  var registered_local_completion = null;
  var last_seen_record = null;

  function last_seen_error(jqXHR, textStatus, errorMessage) {   //Called on failure
  }

  function last_seen_completion(data) {   //Called when everything completed, including callback.
    if(registered_local_completion != null) {
      registered_local_completion(last_seen_record);
    }
  }

  function last_seen_callback(data) {   //Called when we get a response.
    if(data != null && data.result != null) {
      last_seen_record = data.result.rows;
    } else {
      last_seen_record = null;
    }
  }

  function get_last_seen(local_completion, delay) {
    if(delay == null) delay = 0;
    registered_local_completion = local_completion;

    var args = {
      "method": "LastSeen.read",
      "params": {
        "select_on": { "hostname": site_name },  //every active line
        "orderby": null,
        "set": null,              //blank, then no fields to update in a GET
        "result": ['hostname','ping_time']
      },
      "id": Date.getTime(),
      "jsonrpc": 2.0
    }

    url = RPC
    wikk_ajax.delayed_ajax_post_call(url, args, last_seen_callback, last_seen_error, last_seen_completion, 'json', true, delay);
    return false;
  }

  //return a hash of key: function pairs, with the key being the same name as the function.
  //Hence call with wikk_last_seen.function_name()
  return {
    get_last_seen: get_last_seen,
    last_seen_record: last_seen_record
  };
})();
