import Vue from 'vue'
import VueRouter from 'vue-router'
Vue.use(VueRouter)

const routes = [
	{
		path: '/',
		name: 'Home',
		component: () => import('@/views/Home.vue')
	},
	{
		path: '/help',
		name: 'ifquantHelp',
		component: () => import('@/views/Help.vue')
	},
	{
		path: '/sample/:sample',
		name: 'ifquantApp',
		component: () => import('@/views/IFQuant.vue')
	}
	
]
const router = new VueRouter({
	mode: "history",
	routes: routes
})
export default router
