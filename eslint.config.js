import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // Keep hook dependency analysis visible while legacy data-loading effects are
      // progressively moved behind query/mutation boundaries.
      "react-hooks/exhaustive-deps": "warn",
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      // Legacy modules currently use broad Supabase row shapes. These rules remain
      // non-blocking until each module is migrated to generated/domain types.
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-empty-object-type": "off",
      "@typescript-eslint/no-require-imports": "off",
      // These legacy modules explicitly document why generated Supabase/domain types are bypassed.
      // Keep the safeguard visible without making the documented compatibility shim fail lint.
      "@typescript-eslint/ban-ts-comment": ["warn", { "ts-nocheck": "allow-with-description" }],
      "@typescript-eslint/no-unused-vars": "off",
      "no-empty": "off",
    },
  },
);
