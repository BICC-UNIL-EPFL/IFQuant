<template>
	<div class="Home container">
		<template v-if="qptiffs.length">
			<h1 class="h3 border-bottom mb-4">List of images to process</h1>
			<div class="row">
				<div class="col mb-2" v-for="qptiff in qptiffs" :key="qptiff.qptiff">
					<div class="card text-white bg-dark pointer">
		 				<div class="card-body">
		 					<h5 class="card-title">
								{{qptiff.sample}}
								<button type="button" class="btn btn-outline-light btn-sm float-right" v-if="qptiff.CMD"  v-clipboard="() => qptiff.CMD" v-clipboard:success="clipboardSuccessHandler" v-b-tooltip.hover title="Copy Docker CMD"><v-icon name="clipboard" scale="0.9" /></button>
							</h5>
							<template v-if="qptiff.CMD">
								<pre class="code text-light">{{qptiff.CMD}}</pre>
								<ul class="bg-secondary text-light p-1 pl-4">
									<li>The <code>nprocesses</code> parameter can be adapted depending on the number of available CPUs. Be aware that the process will also consume more memory.</li>
									<li>The <code>--tmpdir=&lt;TEMPORARY_DIR&gt;</code> parameter can be specified. If enough memory is available, <code>/dev/shm</code> is an option to speed up the process.</li>
								</ul>
								<p class="bg-info p-2">Reload the page once the process is finished.</p>
							</template>
							
							<template v-else>
								<h6 class="text-light">List of required parameter files: </h6>
								<dl class="row">
									<template v-for="(exists,file) in qptiff.paramFiles">
										<dt class="col-4 p-1 text-right" :key="`dt${file}`">{{file}}</dt>
										<dd class="p-1 text-light" :key="`dd${file}`" :class="exists===true?'bg-success col-1':'bg-danger col-5'">{{exists===true?"VALID":exists}}</dd>
										<div :class="exists===true?'col-6':'col-1'"></div>
									</template>
								</dl>
							</template>
		 				</div>
					</div>
				</div>
			</div>
			
		</template>


		<h1 class="h3 border-bottom mb-4">List of samples</h1>
		<div class="row row-cols-1 row-cols-md-2">
			<div class="col mb-2" v-for="sample in samples" :key="sample.sample">
				<div class="card text-white bg-dark pointer" @click="goTo(sample)">
				  <div class="row no-gutters">
				    <div class="col-md-4">
				      <img :src="`${iipURL}?FIF=analyses/${sample.sample}/sqrt_unmixed_images/image_unmixed.tiff&CTW=[0,1,1,0,1,1,1;0,1,0.8,1,0.5,1,0;1,0,0.9,0,0,1,0]&GAM=2&WID=100&CVT=jpg`"  alt="..."  width="100">
				    </div>
						 <div class="col-md-8">
		 					<div class="card-body">
		 						<h5 class="card-title">{{sample.sample}}</h5>
								<template v-if="!sample.ready">
									<span class="spinner-border text-center  text-warning spinner-border-sm" role="status" v-if="!sample.ready"></span>
								  <span class="ml-3 h6 text-warning">indexing in progress...</span>
									
								</template>
		 					</div>
						 </div>
					 </div>
				</div>
			</div>
		</div>
	</div>
</template>

<script>
import { iipURL } from '@/app_config'
import { mapGetters } from 'vuex'
var intervalGetSample
export default {
	name: 'Home',
	computed: {
		...mapGetters({
			samples: 'samples',
			qptiffs: 'qptiffs'
		})
	},
	data () {
		return {
			iipURL: iipURL
		}
	},
	methods: {
		clipboardSuccessHandler () {
			this.$snotify.success("Command copied successfully to the clipboard")
		},
		
		goTo (sample){
			if (sample.ready){
				this.$router.push(`sample/${sample.sample}`)	
			}
			else{
				this.$snotify.warning("Sample indexing in progress...")
			}
		},
		getSamples () {
			this.$store.dispatch('getSamples').then(samples => {
				let index = _.findIndex(samples, s => !s.ready)
				if (index === -1 && intervalGetSample){
					clearInterval(intervalGetSample)
				}
			})
		}
	},
	mounted () {
		let _this = this
		this.$store.dispatch('getSamples').then(samples => {
			let index = _.findIndex(samples, s => !s.ready)
			if (index > -1){
				intervalGetSample = setInterval(() => {
					_this.getSamples()
				},5000)
			}
			else if (intervalGetSample){
				clearInterval(intervalGetSample)
			}
		})
		this.$store.dispatch('getQptiffs')
	},
	beforeDestroy () {
		clearInterval(intervalGetSample)
	},
}
</script>

<style scoped>
.pointer{
	cursor: pointer;
}
code {
	color: yellow;
}
</style>