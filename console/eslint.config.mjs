// ESLint flat config (ESLint v9+ format).
// TypeScript-specific rules from @typescript-eslint become active once
// node_modules is installed (npm install in console/). For the empty
// scaffolding phase, the base JS rules are sufficient.

export default [
  {
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
    },
    rules: {
      "no-console": "warn",
      "no-unused-vars": "error",
      "prefer-const": "error",
    },
  },
];
