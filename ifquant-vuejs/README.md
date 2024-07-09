# IFQuant-VueJS

## Dependencies

See `packages.json` for a full list of dependencies

* [NPM package manager](https://www.npmjs.com/)
* [VueJS](https://v2.vuejs.org) (version 2.7.14)
* [OpenSeaDragon](https://openseadragon.github.io/) (version 3.1.0)
* [axios](https://axios-http.com/) (version 1.2.2)
* [bootstrap-vue](https://bootstrap-vue.org/) (version 2.23.1)
* [d3](https://d3js.org/) (version 5.16.0)
* [fabric](http://fabricjs.com/) (version 4.6.0)
* [lodash](https://lodash.com/) (version 4.17.21)
* [vue-awesome](https://github.com/Justineo/vue-awesome) (version 4.5.0)
* [vuex]() (version 3.6.2)
* [vite]() (version 2.9.15)


## Production

The `dist` directory is used by the IFQuant app. 

## Development

`node_modules` are not distributed. Prior development, ensure to have `npm` available on your system and run

```bash
npm install
npm run dev
```

to setup the development environment and then load it (using Vite).

## Building
```bash
npm run build
```

will update the `dist` content. 

## Patches

The `OpenSeaDragon` library contains a deprecated function call in its version 3.1. A patch has been created (available in the `patches` directory) and is applied by the `patch-package` library during the development and building phases

## Credits

* Robin Liechti, Vital-IT, SIB Swiss Institute of Bioinformatics, Lausanne, Switzerland and BioInformatics Competence Center, University of Lausanne, Switzerland.

