import {defineConfig} from 'vitest/config';
export default defineConfig({test:{include:['services/**/*.test.ts','packages/**/*.test.ts','tests/**/*.test.ts'],exclude:['**/node_modules/**','tests/e2e/**'],testTimeout:15000}});
