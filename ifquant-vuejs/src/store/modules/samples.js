import Vue from 'vue'
import { HTTP } from '@/router/http'

// initial state
const state = {
	samples: [],
	qptiffs: []
}

// getters
const getters = {
	samples: state => state.samples,
	qptiffs: state => state.qptiffs
}

// actions
const actions = {
	getSamples({ commit }){
		return new Promise((resolve,reject) => {
			HTTP.get('/samples').then(res => {
				resolve(res.data);
				commit("SET_SAMPLES",res.data)
			})
				.catch(err => reject(err))
		});
	},
	getQptiffs({ commit }){
		return new Promise((resolve,reject) => {
			HTTP.get('/qptiffs').then(res => {
				resolve(res.data);
				commit("SET_QPTIFFS",res.data)
			})
				.catch(err => reject(err))
		});
	}
}
// mutations
const mutations = {
	SET_SAMPLES (state, samples){
		state.samples = samples
	},
	SET_QPTIFFS (state, qptiffs){
		state.qptiffs = qptiffs
	}
}

export default {
	state,
	getters,
	actions,
	mutations
}
