const postCssPlugin = require("esbuild-style-plugin");

require("esbuild")
  .build({
    entryPoints: ["src/main.ts"],
    outfile: "priv/static/app.js",
    bundle: true,
    minify: true,
    plugins: [
      postCssPlugin({
        postcss: {
          plugins: [require("tailwindcss"), require("autoprefixer")],
        },
      }),
    ],
  })
  .catch(() => {
    process.exit(1);
  });
