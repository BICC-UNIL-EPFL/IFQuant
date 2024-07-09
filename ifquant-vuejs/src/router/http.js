import axios from 'axios'
import { serverURL, iipURL } from '@/app_config'


export var HTTP = axios.create({ baseURL: serverURL })
export var IIP = axios.create({ baseURL: iipURL })

HTTP.interceptors.response.use(function (response) {
	return response
}, function (error) {
	if (error.response.status > 299) return Promise.reject(error.response.data)
	else return Promise.reject(error)
})

IIP.interceptors.response.use(function (response) {
	return response
}, function (error) {
	if (error.response.status > 299) return Promise.reject(error.response.data)
	else return Promise.reject(error)
})