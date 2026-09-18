shader_type spatial;
uniform vec4 stone_color : source_color = vec4(0.3,0.32,0.31,1);
uniform float grain_scale = 180.0;
varying vec3 world;
varying vec4 tint;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;tint=COLOR;}
void fragment(){
 float grain=noise(world*grain_scale);
 ALBEDO=stone_color.rgb*tint.rgb*(0.65+0.65*grain+0.25*noise(world*23.0))+vec3(smoothstep(0.67,0.83,grain)*0.07);
 ROUGHNESS=0.94;
 NORMAL=normalize(NORMAL-vec3(dFdx(grain),dFdy(grain),0)*0.18);
}
