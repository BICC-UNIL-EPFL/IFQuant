<template>
	<div id="app">
		<vue-snotify></vue-snotify>
		<nav-header></nav-header>		
		<div class="container-fluid app-body">
			<div class="row">

				<main role="main" class="col-md-12 ml-sm-auto px-md-4">
					<!-- content -->
					<router-view style="margin-top:35px;margin-bottom:60px"/>
				</main>
			</div>
		</div>

		<!-- footer -->
		<b-navbar toggleable="md" type="dark" variant="dark" fixed='bottom' id="bottomNavBar">
		<b-navbar-brand  href="https://bix.unil.ch/"  tag='h4' class="mr-auto">© SIB Swiss Institute of Bioinformatics &amp; UNIL / BICC {{year}}
	</b-navbar-brand>
</b-navbar>

</div>
</template>


<script>
import navHeader from '@/components/navheader.vue'
export default {
	components: { navHeader },
	name: 'App',
	data(){
		return{
		}
	},
	computed: {		
		year () {
			return new Date().getFullYear()
		}
	},
	watch: {
		$route (to) {
			if (to.path.indexOf('/sample/') > -1) {
				document.getElementById('bottomNavBar').style.display = 'none'
			}
			else{
				document.getElementById('bottomNavBar').style.display = 'block'
			}
		}
	}
}
</script>


<style>
body {
  font-size: .875rem;
  font-family: 'Avenir', Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
/*  text-align: center;*/
	background-color: #000;
	color: #FFF;
}

div.app-body {
	margin-top: 50px;
}

.big-badge{
	font-size:90% !important;
}	
.pointer{
	cursor:pointer;
}
.ban{
	cursor:not-allowed;
}

.uppercase{
	text-transform:uppercase;
}

.has-error{
	color:#dc3545;
}
.has-error input{
	border:1px solid #dc3545 !important;
}
.has-error input:focus{
	border:1px solid #dc3545;
	box-shadow:0 0 0 0.15rem #F8E6E0 !important;
}
.has-error select{
	border:1px solid #dc3545 !important;
}
.has-error select:focus{
	border:1px solid #dc3545;
	box-shadow:0 0 0 0.15rem #F8E6E0 !important;
}


.has-error small{
	float:left;
	margin-top:5px;
	font-style:italic;
	font-size:11px;
}

a.navbar-brand {
	color: #CCC;
	font-size: 11pt;
}
.fa-icon {
	display: inline-block;
	fill: currentColor;
	overflow: visible;
}

</style>