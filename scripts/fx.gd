extends RefCounted
class_name KartFX
## Centralized shader / particle FX for the pseudo-3D Mario-Kart look. All shaders
## are inline Shader.code (no .gdshader import needed). Materials expose params the
## race scene updates each frame (time / intensity).

# ---- full-screen speed lines (canvas shader) --------------------------------
static func speed_lines() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode blend_add;
uniform float intensity = 0.0;
uniform float time = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float streak = smoothstep(0.72, 1.0, fract(a * 26.0 - time * 3.5));
	streak *= smoothstep(0.68, 1.0, fract(a * 13.0 + time * 1.7));
	float edge = smoothstep(0.20, 0.52, r);
	float v = edge * streak * intensity;
	COLOR = vec4(1.0, 1.0, 1.0, v * 0.55);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

# ---- item-box rainbow shimmer (spatial shader) ------------------------------
static func item_shimmer() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;
uniform float time = 0.0;
vec3 hue(float h){ return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }
void fragment() {
	float h = fract(UV.x + UV.y * 0.5 + time * 0.3);
	vec3 c = hue(h);
	ALBEDO = c;
	EMISSION = c * 1.8;
	ALPHA = 0.7;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

# ---- soft round shadow blob (spatial shader on an upward quad) ---------------
static func shadow_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(1.0, 0.15, r) * 0.42;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

# ---- drift spark emitter (mini-turbo charge tinted) -------------------------
static func drift_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 22
	p.lifetime = 0.42
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3(0, 0.4, 1)          # spray up-and-back
	p.spread = 32.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("#39d0ff")
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	p.mesh = mesh
	p.color = Color("#bfefff")
	return p

## Mini-turbo tier color from drift charge (blue -> orange -> purple, like MK).
static func charge_color(charge: float, needed: float) -> Color:
	if charge >= needed:
		return Color("#c86bff")       # full purple turbo
	elif charge >= needed * 0.55:
		return Color("#ff9d2e")       # orange
	return Color("#39d0ff")           # blue
