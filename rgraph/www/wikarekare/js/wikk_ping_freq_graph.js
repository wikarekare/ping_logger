var wikk_ping_freq_graph = ( function() {
  // MIT License Wikarekare.org rob@wikarekare.org

  var ping_svg_obj = null;
  var draw_div_id = null;


  function graph_ping_histogram(result) {
    if (ping_svg_obj != null) {
      RGraph.SVG.clear(ping_svg_obj.svg);
    }

    var labelsAboveError = [];
    for( var i = 0; i < result.nbuckets; i++ ) {
      labelsAboveError[i] = '';
    }
    labelsAboveError[result.nbuckets] = result.buckets[result.nbuckets];

    ping_svg_obj =  new RGraph.SVG.Bar({
        id: draw_div_id,
        data: result.buckets,
        options: {
          title: "Ping time Distribution (ms) " + result.hostname,
          key: ['Mean ' + result.mean, 'Std Dev ' + result.stddev, 'min ' + result.min, 'max ' + result.max ],
          keyColors: ['#ffffff','#ffffff', '#ffffff', '#ffffff'],

          yaxisScaleMin: 0,
          yaxisScaleMax: result.max_count,
          yaxisScaleDecimals: 0,
          yaxisTitle: 'Frequency',

          xaxisTickmarksCount: 0,
          xaxisTickmarks: false,
          xaxis: true,
          xaxisLinewidth: 1,
          xaxisLabelsAngle: 45,
          xaxisTitle: 'ms',

          backgroundGridVlines: false,
          backgroundGridHlines: false,
          backgroundGridBorder: false,
          backgroundGrid: false,

          textSize: 10,
          xaxisLabels: result.bucket_labels,
          marginTop: 55,
          marginRight: 35,
          marginLeft: 70,
          marginBottom: 80,

          marginInner: 0,

          labelsAbove: true,
          labelsAboveSize: 8,
          labelsAboveSpecific: labelsAboveError
        }
    }).draw();
  }

  function init(the_draw_div_id) {
    draw_div_id = the_draw_div_id;
  }

  return {
    init: init,
    graph_ping_histogram: graph_ping_histogram
  };
})();
