module.exports = {
  content: [
    "./app/views/**/*.{html,html.erb,erb}",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/components/**/*.{html,html.erb,erb,rb}"
  ],
  theme: {
    extend: {
      fontFamily: {
        display: ['"JetBrains Mono"', "ui-monospace", "monospace"],
        sans:    ['"Inter"', "system-ui", "sans-serif"],
        mono:    ['"JetBrains Mono"', "ui-monospace", "monospace"]
      },
      colors: {
        ink:   "#0a0a0a",
        paper: "#fafaf7",
        accent:"#ff4500"
      }
    }
  },
  plugins: []
}
