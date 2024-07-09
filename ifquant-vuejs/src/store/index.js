import Vue from 'vue'
import Vuex from 'vuex'
import samples from './modules/samples.js'
import ifquant from './modules/ifquant.js'

Vue.use(Vuex)


export default new Vuex.Store({
	modules: {
		samples,
		ifquant
	}
})
