import 'mutationobserver-shim'
import Vue from 'vue';
import './plugins/bootstrap-vue'
import './plugins/axios'

import App from './App.vue';
import store from './store'
import router from './router'
import _ from 'lodash';
import Snotify, { SnotifyPosition } from 'vue-snotify'
import 'vue-snotify/styles/material.css'; // or dark.css or simple.css
import 'vue-awesome/icons'
import Icon from 'vue-awesome/components/Icon'
import Clipboard from 'v-clipboard'

const options = {
	toast: {
		position: SnotifyPosition.rightTop
	},
	global: {
		preventDuplicates: true,
	}
}

Vue.use(Snotify, options)
Vue.use(Clipboard)
Vue.component('v-icon', Icon)
Vue.config.productionTip = false
Vue.config.devtools = true;

window._ = _

new Vue({
  render: (h) => h(App),
	router,
	store
}).$mount('#app');