import { defineConfig } from 'vite'
import { createVuePlugin as vue } from "vite-plugin-vue2";
import pluginRewriteAll from 'vite-plugin-rewrite-all';
const path = require("path");
// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue(),pluginRewriteAll()],
	assetsInclude: ['**/*.md'],
  resolve: {
     alias: {
       "@": path.resolve(__dirname, "./src"),
			 vue: 'vue/dist/vue.js',
			 Icon: 'vue-awesome/components/Icon.js'
     },
		 preserveSymlinks: true
   },
	 server: {
		 port: 8081
	 },
	 preview: {
		 port: 8082
	 },
	 base: '/'
	 
})