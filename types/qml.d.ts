// Globals the plugin logic modules see: QML provides Qt and console at run
// time; under Node (the tests) `module` is CommonJS. Declared for
// TypeScript's check of the JSDoc (tsconfig.json), not shipped anywhere.
declare var module: { exports: any } | undefined
declare var Qt: any
declare var console: { log(...args: any[]): void; warn(...args: any[]): void; error(...args: any[]): void }
