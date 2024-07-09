import {HTTP} from '@/router/http'
import Vue from 'vue'
const state = {
	ifquantDensities: {
		channels: {},
		threshold: 0,
		cursor: {
			posX: 0,
		},
	}
}

// getters
const getters = {
	ifquantDensities: (state) => state.ifquantDensities,
}

// actions
const actions = {
	getIfquantDensitiesData({state, commit}, params) {
		return new Promise((resolve, reject) => {
			if (_.keys(state.ifquantDensities.channels).length > 1) {
				resolve(state.ifquantDensities.channels)
			} else {
				return HTTP.get(`/${params.sample}/densities/${params.cellType}`)
					.then((res) => {
						commit('SET_IFQUANT_DENSITIES_CHANNELS', res.data)
						resolve(res.data)
					})
					.catch((err) => reject(err))
			}
		})
	}
}
// mutations
const mutations = {
	RESET_DENSITIES(state) {
		state.ifquantDensities.cursor.posX = 0
		state.ifquantDensities.channels = {}
	},
	SET_DENSITY_THRESHOLD(state, value) {
		state.ifquantDensities.threshold = value
	},
	SET_IFQUANT_DENSITIES_CHANNELS(state, data) {
		state.ifquantDensities.channels = data
	},
	SET_CURSOR_X (state, x) {
		state.ifquantDensities.cursor.posX = x
	}
	
}

export default {
	state,
	getters,
	actions,
	mutations,
}
