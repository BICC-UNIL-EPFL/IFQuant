<template>
	<div class="smoothScatter">
		<div :id="`chart${channelx}${channely}`" :ref="`chart${channelx}${channely}`" class="chart" :style="`height: ${width+margin}px; width: ${width+margin}px`"></div>
	</div>
</template>

<script>
import { mapGetters } from 'vuex'
import { HTTP } from '@/router/http'
import * as d3 from "d3"
export default {
	name: 'smoothScatter',
	props: ['sample','channelx','channely','thresholdx','thresholdy','canEdit','tumorChannel','cellType'],
	computed: {
		...mapGetters({
			ifquantDensities: 'ifquantDensities' 
		}),
		cursor () {
			return this.ifquantDensities.cursor
		},
		xData () {
			const _this = this
			let labels = _.uniq(_.map(_this.data, d => d[0]))
			return labels;
		},
		yData () {
			const _this = this
			let labels = _.uniq(_.map(_this.data, d => d[1]))
			return labels;
		}
	},
	data () {
		return {
			margin: 30,
			width: 100,
			maxX: 1,
			maxY: 1,
			xThreshold: 1,
			yThreshold: 1,
			xScale: null,
			yScale: null,
			xDomain: [],
			yDomain: [],
			xName: '',
			yName: ''
		}
	},
	methods: {
		renderGraph() {
			// create canvas
			const _this = this
			const margin = _this.margin
			const width = _this.width+margin, height = _this.width+margin
			var svg = d3.select(`#chart${_this.channelx}${_this.channely}`)
				.append("svg")
				.attr("width", width)
				.attr("height", height);

			_this.xDomain = [0,_this.maxX]
			_this.yDomain = [0,_this.maxY]
			var xDomain = _this.xDomain
			var yDomain = _this.yDomain
			_this.xScale = d3.scaleSqrt().range([0, _this.width]).domain(xDomain);
			_this.yScale = d3.scaleSqrt().range([_this.width, 0]).domain(yDomain);
			var xScale = _this.xScale
			var yScale = _this.yScale
			
			const yAxis = d3.axisLeft(yScale).ticks(5);
			svg.append("g")
				.attr("transform", "translate("+margin+",0)")
				.call(yAxis);
			const xAxis = d3.axisBottom(xScale).ticks(5);
			svg.append("g")
				.attr("transform", "translate("+margin+","+_this.width+")")
				.call(xAxis);
			
			var g = svg.append("g");
			
			g.append("text")
				.attr("x", width - 5)
				.attr("y", height - 5)
				.style("text-anchor", "end")
				.style("fill", "#FFF")
				.text(_this.xName);
			
			var label = g.append("text")
				.attr("x", 35)
				.attr("y", height - 5)
				.style("text-anchor", "start")
				.style("fill", "#FFF");

			// create crosshairs
			var crosshair = g.append("g")
				.attr("class", "line");

			// create horizontal line
			crosshair.append("line")
				.attr("id", "crosshairX"+_this.channelx+_this.channely)
				.attr("class", "crosshair crosshairX")
				.style("stroke-dasharray", ("3, 3"))
				.attr("x1", xScale(xDomain[0])+margin)
				.attr("y1", yScale(_this.yThreshold))
				.attr("x2", xScale(xDomain[1])+margin)
				.attr("y2", yScale(_this.yThreshold));

			// create horizontal line
			crosshair.append("line")
				.attr("id", "crosshairLive"+_this.channelx+_this.channely)
				.attr("class", "crosshair crosshairLive");

			// create vertical line
			crosshair.append("line")
				.attr("id", "crosshairY"+_this.channelx+_this.channely)
				.attr("class", "crosshair crosshairY")
				.style("stroke-dasharray", ("3, 3"))
				.attr("x1", xScale(_this.xThreshold)+margin)
				.attr("y1", yScale(yDomain[0]))
				.attr("x2", xScale(_this.xThreshold)+margin)
				.attr("y2", yScale(yDomain[1])-margin);

			g.append("rect")
				.attr("class", "overlay")
				.attr("width", width)
				.attr("height", height)
				.on("mouseover", function() {
					crosshair.style("display", null);
					// _this.$store.commit("SET_CURSOR_CHANNEL",_this.channelx)
				})
				.on("mouseout", function() {
					crosshair.select('#crosshairLive'+_this.channelx+_this.channely).style("display", "none");
					label.text("");
					_this.$store.commit("SET_CURSOR_X",0)	
				})
				.on("mousemove", function() {
					var mouse = d3.mouse(this);
					var x = mouse[0];
					var y = mouse[1];
					if (x < margin || y < margin) {
						crosshair.select('#crosshairLive'+_this.channelx+_this.channely).style("display", "none");
					}
					else {
						crosshair.select('#crosshairLive'+_this.channelx+_this.channely).style("display", null);
					}

					label.text(function() {
						return _this.xName+"=" + Math.round(xScale.invert(x-margin)*100)/100;
					});
					if (x !== _this.cursor.posX){
						_this.$store.commit("SET_CURSOR_X",x)	
					}
					
				})
				.on("click", function() {
					if (!_this.canEdit) {
						_this.$snotify.warning('Threshold update forbidden')
					} else if (_this.cellType === _this.tumorChannel) {
						_this.$snotify.warning('Please use the tissue segmentation panel to adjust '+_this.tumorChannel+' thresholds')
					} else {
						const value = Math.round(xScale.invert(d3.mouse(this)[0] - margin) * 100) / 100
						_this.$store.commit('SET_DENSITY_THRESHOLD', value)
						_this.$emit('set-threshold', value)
					}
				});
		}
		
	},
	mounted () {
		const _this = this
		let imagePanelWidth = document.querySelector('#imagePanel').offsetWidth
		let leftPanelWidth = document.querySelector('#leftPanel').offsetWidth
		_this.width = (imagePanelWidth - leftPanelWidth)/6
		if (_this.width > 200) _this.width = 200
		HTTP.get(`/${this.sample}/density_data?channelX=${this.channelx}&channelY=${this.channely}`).then(res => {
			_this.maxX = +res.data.score_x_max
			_this.maxY = +res.data.score_y_max
			_this.xName = res.data.channel_x
			_this.yName = res.data.channel_y
			_this.xThreshold = this.thresholdx
			_this.yThreshold = this.thresholdy
			_this.$store.commit("SET_DENSITY_THRESHOLD",_this.xThreshold)
			_this.renderGraph()
		})
		HTTP.get(`/${this.sample}/density?channelX=${this.channelx}&channelY=${this.channely}`, {
			responseType: 'arraybuffer',
			headers: {
				'Accept': 'application/png'
			}
		}).then(res2 => {
			let b64 = btoa(new Uint8Array(res2.data).reduce(function (data, byte) {
				return data + String.fromCharCode(byte)
			}, ''))
			var mimeType = res2.headers['content-type'].toLowerCase()
			_this.$refs[`chart${_this.channelx}${_this.channely}`].style.backgroundImage = 'url(data:' + mimeType + ';base64,' + b64 +')'
			_this.$refs[`chart${_this.channelx}${_this.channely}`].style.backgroundRepeat = 'no-repeat'
			_this.$refs[`chart${_this.channelx}${_this.channely}`].style.backgroundSize = `${_this.width}px ${_this.width}px`
			_this.$refs[`chart${_this.channelx}${_this.channely}`].style.backgroundPosition = '30px 0px'
		})
	},
	watch: {
		"cursor": {
			handler (n) {
				if (n.posX>=30) {
					d3.select('#crosshairLive'+this.channelx+this.channely).style("display", null)					
				}
				else{
					d3.select('#crosshairLive'+this.channelx+this.channely).style("display", 'none')					
				}
				d3.select("#crosshairLive"+this.channelx+this.channely)
					.attr("x1", n.posX)
					.attr("y1", this.yScale(this.yDomain[0]))
					.attr("x2", n.posX)
					.attr("y2", this.yScale(this.yDomain[1])-30);					
			},
			deep: true
		},
		"ifquantDensities.threshold" (value) {
			this.xThreshold = value
			if (this.xScale) {
				d3.select("#crosshairY"+this.channelx+this.channely)
					.attr("x1", this.xScale(this.xThreshold)+30)
					.attr("x2", this.xScale(this.xThreshold)+30)	
			}
		},
		thresholdx (value,old) {
			if (value && value !== old) {
				this.$store.commit("SET_DENSITY_THRESHOLD",value)
			}
		}
	}
}
</script>

<style>

svg {
	font: 11px sans-serif;
}

.line .crosshair {
	fill: none;
	stroke-width: 2px;
}
.line .crosshairX {
	stroke: #096;
}
.line .crosshairLive {
	stroke: #0C0 !important;
}
.line .crosshairY {
	stroke: #096;
}
.overlay {
	fill: none;
	stroke: black;
	pointer-events: all;
	stroke-width: 0px;
}
svg {
	shape-rendering: crispEdges;
}


</style>
