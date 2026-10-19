shader_type sky;
// The sky. The web game's dome shader (exterior/sky.js, wxSky), line for line: the day's colors (deeper overhead,
// paler toward the horizon), the sun's disc and its glare, the low pink or orange glow some mornings and evenings,
// a moon at night and the stars coming out, twinkling (fewer down low, gone behind cloud and fog).

uniform vec3 uZen;
uniform vec3 uHor;
uniform vec3 uSun = vec3(0.0, 1.0, 0.0);
uniform vec3 uSunC = vec3(1.0);
uniform vec3 uMoon = vec3(-0.5, 0.3, -0.8);
uniform vec3 uGlowC;
uniform float uSunUp;
uniform float uMoonK;
uniform float uStar;
uniform float uT;
uniform float uGlow;
uniform vec3 uFogC;
uniform float uFog;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = d.y;
	vec3 col = mix(uHor, uZen, smoothstep(0.0, 0.55, max(e, 0.0)));
	col = mix(col, uHor * 0.8, 1.0 - smoothstep(-0.2, 0.0, e)); // under the horizon
	vec2 sh = normalize(uSun.xz + vec2(1e-4));
	float side = 0.5 + 0.5 * dot(normalize(d.xz + vec2(1e-4)), sh);
	col += uGlowC * uGlow * exp(-max(e, 0.0) * 4.5) * smoothstep(-0.25, 0.0, e) * (0.2 + 0.8 * side * side); // the glow: low, and strongest toward the sun
	float sd = dot(d, uSun);
	col += uSunC * uSunUp * (smoothstep(0.99955, 0.99975, sd) * 8.0 + pow(max(sd, 0.0), 350.0) * 0.9 + pow(max(sd, 0.0), 10.0) * 0.12);
	if (uStar > 0.003) {
		vec3 sc = vec3(0.0);
		for (int l = 0; l < 2; l++) { // a fine field of faint ones, a few bright ones
			float fl = float(l);
			float sz = l == 0 ? 160.0 : 64.0;
			float thr = l == 0 ? 0.986 : 0.994;
			vec3 p = d * sz;
			vec3 c = floor(p);
			float hh = h3(c + fl * 17.0);
			if (hh > thr) {
				vec3 o = vec3(h3(c + 1.3), h3(c + 2.7), h3(c + 5.1)) - 0.5;
				float b = (1.0 - smoothstep(0.0, l == 0 ? 0.24 : 0.3, length(p - c - 0.5 - o * 0.45))) * (0.35 + 0.65 * (hh - thr) / (1.0 - thr)) * (l == 0 ? 0.9 : 2.2);
				b *= 0.55 + 0.45 * sin(uT * (1.3 + 4.5 * h3(c + 9.2)) + 6.283 * h3(c + 3.3)); // twinkling, each at its own rate
				sc += b * mix(vec3(0.72, 0.84, 1.0), vec3(1.0, 0.86, 0.68), h3(c + 7.7));
			}
		}
		col += sc * 1.7 * uStar * smoothstep(0.02, 0.3, e);
	}
	float md = dot(d, normalize(uMoon));
	if (uMoonK > 0.0) {
		float disc = smoothstep(0.99972, 0.99978, md);
		float mare = 0.78 + 0.22 * smoothstep(-0.3, 0.6, sin(d.x * 140.0 + 1.3) * sin(d.y * 110.0 + d.z * 90.0 + 0.7));
		col = mix(col, vec3(0.86, 0.85, 0.78) * mare * (0.75 + 0.25 * smoothstep(0.99972, 0.99995, md)), disc * uMoonK)
			+ vec3(0.45, 0.52, 0.68) * (pow(max(md, 0.0), 2500.0) * 0.35 + pow(max(md, 0.0), 120.0) * 0.06) * uMoonK;
	}
	col = mix(col, uFogC, uFog * (0.55 + 0.45 * (1.0 - smoothstep(0.0, 0.6, e))));
	COLOR = col;
}
