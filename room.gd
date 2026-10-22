extends Node
## The web game's lighting: a surface is lit by where it is. Not by lights: by which room it's in and whether that
## room's switch is on, with daylight falling in through the storefront glass and fading toward the back, and outside
## the building the sun, the moon, or somewhere in between. It stops dead at the walls: a switched-off break room is
## dark even with the store lit next door.
## From the web game: the room shader in store/core.js (ROOM_FRAG, and how it's hooked into every lit material),
## store/lounge.js (applyLighting: which switch feeds which room), store/shift.js (todTick: the daylight's colour
## through the glass), and the colours set in store/theater.js and exterior/lot.js. The rooms' boxes are the web
## game's, from data/interact.json.
##
## Every lit material in the level is swapped, as the game starts, for one that does this (the level's own file isn't
## touched). Things the web game draws unlit (screens, signs, the inside of Tony's) stay as they are.
## Past the web game, on purpose: its daylight is a fade toward the back with no shadows, so a dark store was still
## evenly grey. Here daylight comes in through the storefront as real light that things stand in the way of, and the
## screens light the room with what's on them (both in lights.gd).
## And further past it (also on purpose: the surfaces are flat colour, so the light has to do the work). The room's
## light goes in as ambient light rather than as a glow of the surface's own, so the screen-space passes can work on
## it: corners, the undersides of shelves and where things meet the floor darken (SSAO), colour bounces a little off
## what's near (SSIL). The real lights (lamps, screens, daylight through the glass, light through a doorway) are
## added by light() below. Outdoors the sun, or the moon, whichever's the stronger, is a real light with shadows
## (main.tscn's Sun); the other stays a shadowless term here. Lit panels and signs bloom, and the air's faintly hazy
## where a real light crosses it (shafts in from the storefront, the lot's lamps at night, the projector's beam).
## fancy() turns the lot of it off and on (the menu's "Lighting effects").

const SHADER := """
shader_type spatial;
render_mode MODES;
global uniform vec4 uZone;      // front, aisles, lounge switches (0..1, flicker-aware), daylight 0..1
global uniform vec4 uBoh;       // hall, break room, restroom switches, the closet bulb
global uniform vec4 uFloorBox;  // sales floor: x0, x1, back wall z, ceiling
global uniform vec4 uBohBox;    // back of house: x0, x1, hall|rooms z, z1
global uniform vec4 uLobbyBox;
global uniform vec4 uThBox;     // auditorium: x0, x1, z0, z1
global uniform vec2 uTall;      // the booth's floor (a little under it), the booth's and auditorium's ceiling
global uniform float uBoothZ;   // the booth, over the lobby from here back
global uniform vec2 uShaft;     // the stairwell up to it, in the lobby's corner: from this x, this z
global uniform float uBoothLight;  // its switch
global uniform float uStairLight;  // the stairwell's
global uniform sampler2D uPanels : filter_linear_mipmap, repeat_disable;   // the sales floor's ceiling panels from below (lights.gd's _panel_map)
global uniform vec4 uPanelBox;  // where that map is: x0, z0, its width, its depth
const float PANEL_REFLECT = 12.0;  // how bright a panel looks in a sleeve, the tile
global uniform vec2 uZoneSplit;  // the sales floor's zones: front | aisles z, aisles | lounge z
global uniform vec3 uBohSplit;  // break room | restroom x, ceiling, closet | hall x
global uniform vec2 uThLight;   // x = lobby switch, y = theater house-lights switch
global uniform float uThSconce;
global uniform vec3 uInSky; global uniform vec3 uInGround; global uniform vec3 uInAmb; global uniform vec3 uInDirC; global uniform vec3 uInDir;
global uniform vec3 uSunSky; global uniform vec3 uSunGround; global uniform vec3 uSunC; global uniform vec3 uSunDir;
global uniform vec3 uMoonSky; global uniform vec3 uMoonGround; global uniform vec3 uMoonC; global uniform vec3 uMoonDir;
global uniform vec3 uDayC; global uniform vec3 uNightC;
global uniform float uSunReal;  // 1: the sun's the real light (the moon's a term here); 0: the other way about
global uniform vec4 uFog;       // from indoors: the weather's fog on what's out there (its colour, how thick). The engine's own is off while you're inside: it would fog the room too
const float ZONE_BLEED = 2.5;    // m: a lit zone's light past its edge, down to a third this far on
const float VID_TV = 0.9;        // how much of the picture's colour the TV throws on what's right by it...
const float VID_TV_R = 3.0;      // ...halved this far out
const float VID_FLOOR = 0.06;    // the monitors over the aisles: a little of it the whole floor over
const float VID_THEATER = 0.3;   // the theater's screen: on everything in the house (a dim room with a film on: lights.gd's HOUSE)
global uniform vec4 uVid;       // the picture that's playing: its colour, averaged (rgb), how much it's on (a). It lights the room it's in, over whatever else is (lights.gd)
global uniform vec3 uVidAt;     // the lounge TV, a little out from its face
uniform vec4 albedo : source_color = vec4(1.0);
uniform float shine = 0.0;      // 0 matte; up to 1, a plastic sleeve: a glint of the real lights (ponytail: no SSR; tile and plastic give back a few percent, too faint to see over what it cost)
uniform sampler2D tex : source_color, FILTER, repeat_enable;
uniform bool use_tex = false;
uniform vec3 tint = vec3(1.0);   // LOOK: the store's colours, put to rights (a wall's paint, the carpet worn grey)
uniform float desat = 0.0;
uniform bool carpet = false;     // LOOK's third: the carpet's pile, worn paths and confetti flecks (carpet() below)
uniform bool use_vcol = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 emission = vec3(0.0);
uniform sampler2D emission_tex : source_color, FILTER, repeat_enable;
uniform bool use_emission_tex = false;   // (a lit sign, a poster: its own picture, glowing)
uniform float scissor = 0.5;
varying vec3 P;
varying vec3 wN;
varying vec3 vAlb;   // the surface's own colour, for light()
varying float vIn;   // 1 indoors: the sun's not let in (daylight comes through the glass as lights of its own)
varying float vFog;  // how much of it the fog out there has taken

void vertex() {
	P = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wN = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	UV = UV * uv_scale.xy + uv_offset.xy;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 carpet_look(vec3 c, vec2 q) {   // a commercial carpet of the time, by where on the floor: the pile's grain, a slow mottle, worn paler where feet go, and confetti flecks
	float near = clamp(1.0 - 40.0 * length(fwidth(q)), 0.0, 1.0);   // (the fine stuff fades with distance, before it can shimmer)
	float pile = mix(1.0, 0.9 + 0.2 * hash(floor(q * 180.0)), near);
	float mottle = 0.92 + 0.16 * vnoise(q * 3.0);
	float worn = smoothstep(0.55, 0.85, vnoise(q * 0.35 + 7.0));   // (patches, metres across)
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))) * 1.25, 0.35 * worn) * pile * mottle;
	vec2 cell = floor(q * 14.0);
	vec2 f = fract(q * 14.0) - 0.5;
	float h = hash(cell + 3.1);
	if (h < 0.12) {   // a fleck: a short dash, turned any way
		float ang = hash(cell + 9.7) * 6.2832;
		vec2 d = vec2(cos(ang) * f.x + sin(ang) * f.y, -sin(ang) * f.x + cos(ang) * f.y);
		float on = (1.0 - smoothstep(0.2, 0.26, abs(d.x))) * (1.0 - smoothstep(0.06, 0.1, abs(d.y)));
		vec3 fleck = h < 0.04 ? vec3(0.62, 0.22, 0.42) : h < 0.08 ? vec3(0.2, 0.55, 0.55) : vec3(0.78, 0.66, 0.3);
		c = mix(c, fleck * mottle, on * 0.7 * mix(0.35, 1.0, near));
	}
	return c;
}

void fragment() {
	vec4 a = albedo;
	if (use_tex) a *= texture(tex, UV);
	if (use_vcol) a.rgb *= COLOR.rgb;
	a.rgb = mix(a.rgb, vec3(dot(a.rgb, vec3(0.3, 0.59, 0.11))), desat) * tint;
	if (carpet) a.rgb = carpet_look(a.rgb, P.xz);
	ALPHA_CODE
	vec3 rN = normalize(wN) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 fl = mix(uInGround, uInSky, 0.5 * rN.y + 0.5) + uInAmb + uInDirC * max(dot(rN, uInDir), 0.0);   // one room's worth of fluorescents
	float day = uZone.w;
	vec3 rl;
	vIn = 1.0;
	vFog = 0.0;
	if (P.x > uFloorBox.x && P.x < uFloorBox.y && P.z > -0.05 && P.z < uFloorBox.z && P.y < uFloorBox.w) {
		// the sales floor: three switch zones along z (lights.gd's FLOOR_SPLIT, moved with the store's depth), each lit right to
		// its edge and its light carrying on past it into the next, dying away over a few metres; daylight in through the glass
		float f1 = exp(-max(P.z - uZoneSplit.x, 0.0) / ZONE_BLEED);
		float f2 = exp(-max(max(uZoneSplit.x - P.z, P.z - uZoneSplit.y), 0.0) / ZONE_BLEED);
		float f3 = exp(-max(uZoneSplit.y - P.z, 0.0) / ZONE_BLEED);
		float win = exp(-P.z / 9.0);
		float facing = 0.75 + 0.35 * max(-rN.z, 0.0) + 0.2 * max(rN.y, 0.0);
		// (the web game's daylight is all here, unshadowed: (0.42 + 0.9 * win). Here it comes in as real light, with shadows,
		// from lights.gd, and this is only what bounces round: next to nothing at the back)
		rl = max(max(uZone.x * f1, uZone.y * f2), uZone.z * f3) * fl + (day * uDayC + (1.0 - day) * uNightC) * (0.015 + 0.16 * win * win) * facing;
		vec3 tv = P - uVidAt;
		rl += uVid.rgb * uVid.a * (VID_TV / (1.0 + dot(tv, tv) / (VID_TV_R * VID_TV_R)) + VID_FLOOR);   // the TV's glow, a pool round the lounge; and the monitors over the aisles, a little everywhere
	} else if (P.x > uBohBox.x && P.x < uBohBox.y && P.z >= uFloorBox.z && P.z < uBohBox.w && P.y < uBohSplit.y + 0.05) {
		bool closet = P.x > uBohSplit.z && P.z < uBohBox.z;   // the janitor's closet, at the hall's end: one bare bulb, warm
		float lvl = closet ? 0.8 * uBoh.w : P.z < uBohBox.z ? uBoh.x : (P.x < uBohSplit.x ? uBoh.y : uBoh.z);
		rl = (0.03 + 0.97 * lvl) * fl * (closet ? vec3(1.12, 0.95, 0.74) : vec3(1.0));
	} else if (P.x > uLobbyBox.x && P.x < uLobbyBox.y && P.z >= uLobbyBox.z && P.z < uLobbyBox.w && (P.y < uBohSplit.y + 0.05 || P.z >= uBoothZ && P.y > uTall.x && P.y < uTall.y + 0.1)) {   // (and the projection booth over its back, and the stairs up to it: on a switch of their own, a cooler light)
		bool stairs = P.x > uShaft.x && P.z > uShaft.y;
		bool booth = stairs || P.y > uTall.x;
		float lv = stairs ? uStairLight : uBoothLight;
		rl = booth ? ((0.03 + 0.5 * lv) * vec3(1.12, 0.92, 0.7) + (stairs ? vec3(0.0) : 0.06 * (1.0 - lv) * vec3(1.0, 0.12, 0.08))) * fl : (0.04 + 0.96 * uThLight.x) * fl * vec3(1.08, 0.93, 0.80);   // (back here, no tubes: a warm room round its lamps' pools, lights.gd's; the booth with its switch off, the red of its working lights)
	} else if (P.x > uThBox.x && P.x < uThBox.y && P.z >= uThBox.z && P.z < uThBox.w && P.y < uTall.y + 0.1) {
		rl = (0.025 + 0.55 * uThLight.y + 0.12 * uThSconce) * fl * vec3(1.15, 0.82, 0.55);   // house lights + a low warm sconce wash
		rl += uVid.rgb * uVid.a * VID_THEATER;   // the picture, off the screen onto the walls, the ceiling, the seats
	} else {
		vec3 sun = mix(uSunGround, uSunSky, 0.5 * rN.y + 0.5) + uSunC * max(dot(rN, uSunDir), 0.0) * (1.0 - uSunReal);
		vec3 moon = mix(uMoonGround, uMoonSky, 0.5 * rN.y + 0.5) + uMoonC * max(dot(rN, uMoonDir), 0.0) * uSunReal;
		rl = mix(moon, sun, day);
		vIn = 0.0;
		if (uFog.a > 0.0 && !(P.x > 13.0 && P.x < 21.0 && P.z > 0.0 && P.z < 14.0 && P.y < 4.39)) vFog = 1.0 - exp(-uFog.a * length(VERTEX));   // (not in next door, either)
	}
	vAlb = a.rgb;
	ALBEDO = a.rgb * rl * 0.3183099 * (1.0 - vFog);   // the room's light, as the web game's Lambert has it (over pi): what the white ambient light shows, less what SSAO takes
	ROUGHNESS = 1.0 - 0.75 * shine;
	SPECULAR = shine;
	EMISSION = emission * (use_emission_tex ? texture(emission_tex, UV).rgb : vec3(1.0)) * (1.0 - vFog) + uFog.rgb * vFog;
	if (shine > 0.0 && P.x > uFloorBox.x && P.x < uFloorBox.y && P.z > -0.05 && P.z < uFloorBox.z && P.y < uFloorBox.w) {
		// the ceiling's panels in it: the view bounced off the surface, up to the ceiling, and whether there's a panel there
		// (blurrier the further off, and the rougher); next to nothing head on, more the more glancing (Fresnel)
		vec3 V = normalize(P - CAMERA_POSITION_WORLD);
		vec3 R = reflect(V, rN);
		if (R.y > 0.02) {
			float t = (uFloorBox.w - P.y) / R.y;
			vec2 hit = P.xz + R.xz * t;
			float lit = textureLod(uPanels, (hit - uPanelBox.xy) / uPanelBox.zw, log2(1.0 + t * (1.0 - shine) * 3.0)).r;
			float zone = hit.y < uZoneSplit.x ? uZone.x : (hit.y < uZoneSplit.y ? uZone.y : uZone.z);
			float fr = 0.04 + 0.96 * pow(1.0 - clamp(dot(rN, -V), 0.0, 1.0), 5.0);
			EMISSION += vec3(lit * zone * fr * shine * PANEL_REFLECT) * smoothstep(0.02, 0.25, R.y);   // (fading out toward level: on something round, no hard line where the ceiling ends)
		}
	}
}

void light() {   // the real lights, on the surface's own colour (ALBEDO's already the room's light on it)
	if (!(LIGHT_IS_DIRECTIONAL && vIn > 0.5)) {
		SPECULAR_LIGHT += vAlb * LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * 0.3183099 * (1.0 - vFog);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 60.0) * 0.6 * shine * (1.0 - vFog);   // the glint
	}
}
"""

const FLOOR_SHINE := { "vaultbuster_73.jpg": 0.6, "vaultbuster_0.jpg": 0.5 }  # the level's hard floors, by their pictures
# a real store's colours, by the level's pictures or plain colours: [tint, how much of the colour out first]. The web game's
# primaries read as a toy: walls painted a warm yellow, the carpet a worn blue-grey, the uprights navy
const LOOK := { "e8ecf2": [Color("#e9c25c"), 0.0], "vaultbuster_43.jpg": [Color(1.2, 1.35, 1.6), 0.7, "carpet"],"1c4dbb": [Color("#5d79ab"), 0.35] }
const GRADE := """
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float vig = 0.3;     // the corners, this much darker
uniform float grain = 0.03;  // and a film's grain over it all
void fragment() {
	float v = vig * smoothstep(0.3, 0.75, length(UV - 0.5));
	float n = (fract(sin(dot(FRAGCOORD.xy + fract(TIME) * vec2(113.0, 71.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0 * grain;
	float k = v + max(-n, 0.0);   // darker, lighter: mixed toward black and white by those much
	float l = max(n, 0.0);
	COLOR = vec4(vec3(l), k + l);
}
"""
const TONE_EXPOSURE := 1.25  # AgX sits a little darker in the middle than the linear it replaced: this brings it back up

var _shaders := {}
var _made := {}

var _moon_dir := Vector3(-14, 26, -10).normalized()
var _moon_c := Vector3.ZERO
var _fancy := true
var _grade := CanvasLayer.new()  # GRADE, over the picture

@onready var sky: Node3D = $"../Sky"
@onready var lights: Node = $"../Lights"
@onready var sun: DirectionalLight3D = $"../Sun"
@onready var env: Environment = $"../WorldEnvironment".environment


func _enter_tree() -> void:  # (before anything's _ready: tapes.gd keeps hold of the materials it finds)
	var fixed := {  # lin(colour, k), as the web game sets them
		"uInSky": _lin(0xdfe8ff, 1.15), "uInGround": _lin(0x223355, 1.15), "uInAmb": _lin(0xffffff, 0.32), "uInDirC": _lin(0xffffff, 0.55),
		"uInDir": Vector3(3, 10, -6).normalized(),
		"uSunSky": _lin(0xaed4f5, 0.75), "uSunGround": _lin(0x4c6a3c, 0.75), "uSunC": _lin(0xfff3d9, 0.95), "uSunDir": Vector3(12, 30, -8).normalized(),
		"uMoonSky": _lin(0x2c3d68, 0.55), "uMoonGround": _lin(0x05070f, 0.55), "uMoonC": _lin(0xaec2e8, 0.5), "uMoonDir": Vector3(-14, 26, -10).normalized(),
		"uDayC": Vector3.ONE, "uNightC": Vector3(0.035, 0.045, 0.08),  # (night: moonlight + the lot lights through the glass)
	}
	for n: String in fixed:
		glob(n, fixed[n])
	var b: Dictionary = Level.data().lights.boxes
	for pair in [["uFloorBox", b.floor], ["uBohBox", b.boh], ["uLobbyBox", b.lobby], ["uThBox", b.theater]]:
		glob(pair[0], Vector4(pair[1][0], pair[1][1], pair[1][2], pair[1][3]))
	glob("uBohSplit", Vector3(b.bohSplit[0], b.bohSplit[1], b.bohSplit[2]))
	glob("uTall", Vector2(b.tall[0], b.tall[1]))
	glob("uBoothZ", b.booth[2])
	glob("uShaft", Vector2(b.shaft[0], b.shaft[1]))
	var split: Array = preload("res://lights.gd").FLOOR_SPLIT
	glob("uZoneSplit", Vector2(split[0], split[1] + Level.dz))  # (the same lines the ceiling panels are sorted by: lights.gd's zone_at)
	var swapped := light($"../World")
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):  # the hard floors: the tile by the door and the counter, and the hall's
		var gloss: float = FLOOR_SHINE.get(preload("res://level.gd").texture_of(mi), 0.0)
		if gloss > 0.0:
			mi.mesh.surface_get_material(0).set_shader_parameter("shine", gloss)
	print("room light: %d surfaces, %d materials, %d shaders" % [swapped, _made.size(), _shaders.size()])
	_moon_c = fixed.uMoonC


func _ready() -> void:  # the sun (or the moon) as a real light, and what the picture's put through
	sun.visible = true
	sun.light_specular = 0.0
	sun.light_volumetric_fog_energy = 0.0
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS  # (four drew the whole level four times over)
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.06
	get_viewport().msaa_3d = Viewport.MSAA_4X  # (the shelves' edges, the spines and the signs' letters stop crawling as you move)
	get_viewport().anisotropic_filtering_level = Viewport.ANISOTROPY_16X  # (covers and floor sharp down the length of an aisle)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX  # (the brights roll off instead of clipping flat: lit panels, the screens, the sun through the glass)
	env.tonemap_exposure = TONE_EXPOSURE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # (white, at 1: ALBEDO carries the room's light)
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	env.ssao_radius = 0.9
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.0
	env.glow_hdr_threshold = 1.0  # only what's brighter than white blooms: lit panels, the sun's disc
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.0  # (only where a real light crosses the air)
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	_grade.layer = 0  # (under the HUD's words; below 0 the engine drew it over everything, white)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()  # (typed: rect.material.shader = ... didn't take, and drew it plain white)
	sh.code = GRADE
	var m := ShaderMaterial.new()
	m.shader = sh
	rect.material = m
	_grade.add_child(rect)
	add_child(_grade)
	fancy(_fancy)


func fancy(on: bool) -> void:  # the costly part: contact shadows, bounce, bloom, haze, and the sun's shadows
	_fancy = on
	if not is_node_ready():
		return
	env.ssao_enabled = on
	env.ssil_enabled = on
	env.glow_enabled = on
	env.volumetric_fog_enabled = on
	sun.shadow_enabled = on
	lights.fancy(on)


static var globals := {}  # the shader globals as last set (the engine only says what they are in the editor): tools/snapshot.gd keeps them


static func glob(n: String, v: Variant) -> void:  # a shader global (they're the project's: Project Settings > Shader Globals, there in the editor too)
	globals[n] = v
	RenderingServer.global_shader_parameter_set(n, v)


func light(root: Node) -> int:  # everything lit under there, onto the room's light (the level; the cast of people)
	var swapped := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D and m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				mi.mesh.surface_set_material(s, _room_material(m, mi.mesh is ArrayMesh and mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR != 0))
				swapped += 1
	return swapped


func _lin(hex: int, k: float) -> Vector3:
	var c := Color.hex((hex << 8) | 0xff).srgb_to_linear() * k
	return Vector3(c.r, c.g, c.b)


func _room_material(m: StandardMaterial3D, has_colors: bool) -> ShaderMaterial:
	var key := [m, has_colors]
	if _made.has(key):
		return _made[key]
	var modes := PackedStringArray()
	modes.append(["cull_back", "cull_front", "cull_disabled"][m.cull_mode])
	var alpha := ""
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
		alpha = "ALPHA = a.a; ALPHA_SCISSOR_THRESHOLD = scissor;"
	elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		alpha = "ALPHA = a.a;"
		modes.append("blend_mix")
		if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			modes.append("depth_prepass_alpha")
		else:
			modes.append("depth_draw_never" if m.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED else "depth_draw_opaque")
	var nearest := m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST or m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var code := SHADER.replace("MODES", ", ".join(modes)).replace("ALPHA_CODE", alpha).replace("FILTER", "filter_nearest" if nearest else "filter_linear_mipmap")
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code
		_shaders[code] = sh
	var out := ShaderMaterial.new()
	out.shader = _shaders[code]
	out.set_shader_parameter("albedo", m.albedo_color)
	var look: Array = LOOK.get(m.albedo_texture.resource_path.get_file() if m.albedo_texture else m.albedo_color.to_html(false), [])
	if look:
		out.set_shader_parameter("tint", look[0])
		out.set_shader_parameter("desat", look[1])
		out.set_shader_parameter("carpet", look.size() > 2)
	if m.albedo_texture != null:
		out.set_shader_parameter("tex", m.albedo_texture)
		out.set_shader_parameter("use_tex", true)
	out.set_shader_parameter("use_vcol", m.vertex_color_use_as_albedo or has_colors)  # (glTF: a mesh's colours always count)
	out.set_shader_parameter("uv_scale", m.uv1_scale)
	out.set_shader_parameter("uv_offset", m.uv1_offset)
	out.set_shader_parameter("scissor", m.alpha_scissor_threshold)
	if m.emission_enabled:
		var e := m.emission.srgb_to_linear() * m.emission_energy_multiplier
		out.set_shader_parameter("emission", Vector3(e.r, e.g, e.b))
		if m.emission_texture != null:
			out.set_shader_parameter("emission_tex", m.emission_texture)
			out.set_shader_parameter("use_emission_tex", true)
	out.render_priority = m.render_priority
	_made[key] = out
	return out


func _process(_dt: float) -> void:  # applyLighting: the switches' levels and the day, into the materials
	_grade.visible = not $"../HUD".is_full_screen()  # (a film full screen is the film's own picture)
	var z: Dictionary = lights.zone_lvl
	glob("uZone", Vector4(z.front, z.aisles, z.lounge, sky.level))
	glob("uBoh", Vector4(z.hall, z.breakroom, z.restroom, z.closet))
	glob("uThLight", Vector2(z.lobby, lights.house_lights()))  # (up between films, down while one's on: lights.gd)
	glob("uBoothLight", z.booth)
	glob("uStairLight", z.stairwell)
	glob("uSunDir", sky.sun_dir)
	glob("uSunC", Vector3(sky.sun_c.r, sky.sun_c.g, sky.sun_c.b))
	glob("uDayC", sky.day_c)
	# the stronger of the sun and the moon is the real light; its shadows fade out and back in as they change places at dusk and dawn
	var day: float = sky.level
	var real := day >= 0.5
	glob("uSunReal", 1.0 if real else 0.0)
	var c: Vector3 = Vector3(sky.sun_c.r, sky.sun_c.g, sky.sun_c.b) * day if real else _moon_c * (1.0 - day)
	var top := maxf(maxf(c.x, c.y), maxf(c.z, 0.0001))
	sun.light_color = Color(c.x / top, c.y / top, c.z / top).linear_to_srgb()
	sun.light_energy = top / PI  # (the engine's lights are a factor of pi up on the web game's)
	sun.shadow_opacity = clampf(absf(day - 0.5) * 6.0, 0.0, 1.0)
	var dir: Vector3 = sky.sun_dir if real else _moon_dir
	sun.basis = Basis.looking_at(-dir, Vector3.FORWARD)
