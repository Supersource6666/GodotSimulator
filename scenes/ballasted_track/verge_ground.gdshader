shader_type spatial;
uniform bool path = false;
varying vec3 world;
float hash(vec2 p){p=fract(p*vec2(123.34,345.45));p+=dot(p,p+34.345);return fract(p.x*p.y);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float patch=noise(world.xz*0.35)*0.7+noise(world.xz*2.8)*0.3;
 float grain=noise(world.xz*160.0);
 vec3 grass=mix(vec3(0.067,0.087,0.030),vec3(0.145,0.166,0.066),patch);
 vec3 dirt=mix(vec3(0.24,0.185,0.115),vec3(0.38,0.31,0.21),patch);
 ALBEDO=(path?dirt:grass)*(0.93+grain*0.13);
 ROUGHNESS=0.98;
}