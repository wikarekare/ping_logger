var wikk_ping_graph = ( function() {
  var registered_local_completion = null;
  var result = null;

  function ping_data_error_callback(jqXHR, textStatus, errorMessage)
  {   var result_div = document.getElementById('result_div');
      last_result = null;
      result_div.innerHTML='Error:' + jqXHR.status.toString() + '<br>\n' + errorMessage;
  }

  function ping_data_completion(data) {   //Called when everything completed, including callback.
    if(registered_local_completion != null) {
      registered_local_completion(result);
    }
  }

  function ping_data_callback(data) { //should we have extra args ,status,xhr
    result = data.result;
  }

  function graph_data(form_id, local_completion=null) {
    registered_local_completion = local_completion;

    var the_form = document.getElementById(form_id);
    var args = {
      "method": "Pings.read",
      "params": {
        "select_on": { "hostname":   the_form.host.value,
                       "start_time": the_form.start_datetime.value,
                       "end_time":   the_form.end_datetime.value
                      },
        "orderby": null,
        "set": null,
        "result": []
      },
      "id": new Date().getTime(),
      "jsonrpc": 2.0
    }

    url = RPC_URL
    wikk_ajax.delayed_ajax_post_call(url, args, ping_data_callback, ping_data_error_callback, ping_data_completion, 'json', true, 0);

    return false;
  }

  //return a hash of key: function pairs, with the key being the same name as the function.
  //Hence call with wikk_ping.function_name()
  return {
    graph_data: graph_data
  };
})();
