<template>
	<div class="channelDensities px-3">
		<button style="position: absolute; top: 0; right: 0; z-index:101" class="btn btn-link text-light" @click="$emit('close-density')"><v-icon name="times" /></button>
		<div class="row">
			<div v-if="!dataReady"><p class="text-center text-info h4">loading...</p></div>
			<template v-else>
				<template  v-for="(ch,label) in channels" >
					<div class="col mt-3" :key="`data${ch}`" v-if="label!==cellType">
						<h5 class="text-left">{{label}}</h5>
						<smooth-scatter :channelx="ch" :channely="channelx" :sample="sample" :thresholdx="thresholds[cellType].value" :thresholdy="thresholds[label].value"  :canEdit="canEdit" :cellType="cellType" :tumorChannel="tumorChannel" @set-threshold="$emit('set-threshold',$event)"></smooth-scatter>
					</div>
				</template>
			</template>
		</div>
	</div>
</template>

<script>


import { mapGetters } from 'vuex'
import smoothScatter from '@/components/smoothScatter.vue'
export default {
	name: "channelDensities",
	components: { smoothScatter  },
	props: ['sample','cellType','thresholds','tumorChannel','canEdit'],
	data () {
		return {
			testData: [],
			dataReady: false,
			channelx: ''
		}
	},
	computed: {
		...mapGetters({
			ifquantDensities: 'ifquantDensities'
		}),
		channels () {
			let channels = {}
			_.forEach(this.ifquantDensities.channels, (c,l) => {
				if (+c > 0 && +c < 7 && l !== 'autofluorescence') {
					channels[l] = c
				}
			})
			return channels
		},
	},
	methods: {
	},
	mounted () {
		this.$store.dispatch("getIfquantDensitiesData",{sample: this.sample, cellType: this.cellType}).then(() => {
			this.dataReady = true
			this.channelx = (this.ifquantDensities.channels[this.cellType] !== undefined) ? this.ifquantDensities.channels[this.cellType] : null
		})
	}
}
</script>

<style>
	.channelDensities {
		position: relative;
		z-index: 100 !important;
	}
</style>