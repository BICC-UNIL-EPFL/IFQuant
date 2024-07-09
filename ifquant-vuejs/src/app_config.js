export const serverURL = (import.meta.env.DEV) ? 'http://localhost:8088/api/index.php/' : '/api/index.php/'
export const iipURL =  "http://localhost:8089/fcgi-bin/iipsrv.fcgi"

export const siteTitle = `IFQuant`

export const getHeader = function () {
	const headers = {
		'Accept': 'application/json'
	}
	return headers
}

