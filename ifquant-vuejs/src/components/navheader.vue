<template>
	<div class = 'navHeader'>
		<b-navbar toggleable="md" type="dark" variant="dark" fixed='top'>
			<b-navbar-brand href="#">
				<img src="../assets/logo_unil.png" class = 'mx-3' height='34' />
				<img src="../assets/logo_chuv.png" class = 'mx-3' height='34' />
				<img src="../assets/sib_logo_small.gif" class = 'mx-3' height='34' />
				<span class='site-title text-center ml-4 text-center' style="display: inline-block"><router-link to="/">{{siteTitle}}</router-link></span>
			</b-navbar-brand>
			<b-navbar-nav class="ml-auto">
				<button type="button" class="btn btn-link"><router-link class="text-light" to="/help">User manual</router-link></button>
			</b-navbar-nav>
			
		</b-navbar>
	</div>
</template>

<script>
import Vue from 'vue'
import { mapGetters } from 'vuex'
import { siteTitle } from '@/app_config.js'
export default {
	name: 'navHeader',
	data () {
		return {
			siteTitle: siteTitle
		}
	},
	computed: {
		showNav () {
			return (this.$route.path !== '/' && this.$route.path !== '/home')
		},
	}
}

</script>

<style>
span.site-title a {
	color: #FFF;
	font-weight: bold;
	font-size: 32px;
}
span.site-title a:hover{
	text-decoration: none;
}
.feather {
  width: 16px;
  height: 16px;
  vertical-align: text-bottom;
}

</style>