shader_type spatial;
uniform bool path = false;
varying vec3 world;
float hash(vec2 p){p=fract(p*vec2(123.34,345.45));p+=dot(p,p+34.345);return fract(p.x*p.y);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float patch=noise(world.xz*0.35)*0.7+noise(world.xz*2.8)*0.3;
 float grain=noise(world.xz*160.0);
 vec3 grass=mix(vec3(0.10,0.12,0.065),vec3(0.23,0.235,0.145),patch);
 vec3 dirt=mix(vec3(0.20,0.17,0.12),vec3(0.34,0.30,0.23),patch);
 float bare=smoothstep(0.48,0.73,noise(world.xz*0.17+vec2(41.0,8.0)));
 vec3 verge=mix(grass,dirt,bare*0.72);
 ALBEDO=(path?dirt:verge)*(0.86+grain*0.24);
 ROUGHNESS=0.98;
}
