import Vue from 'vue'
import Echarts from 'vue-echarts'

import 'echarts/lib/chart/line'
import 'echarts/lib/chart/bar'
import 'echarts/lib/chart/pie'
import 'echarts/lib/chart/radar'
import 'echarts/lib/chart/treemap'
import 'echarts/lib/chart/sankey'
import 'echarts/lib/chart/scatter'
import 'echarts/lib/chart/custom'
import 'echarts/lib/chart/heatmap'
import 'echarts/lib/chart/boxplot'
import 'echarts/lib/component/tooltip'
import 'echarts/lib/component/toolbox'
import 'echarts/lib/component/brush'
import 'echarts/lib/util/format'
import 'echarts/lib/component/legend'
import 'echarts/lib/component/dataZoom'
import 'echarts/lib/component/visualMapPiecewise'
import 'echarts/lib/component/visualMapContinuous'

Vue.component('chart', Echarts)
