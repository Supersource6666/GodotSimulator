shader_type spatial;
varying vec3 local_pos;
float hash(vec3 p){p=fract(p*0.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z);}
float noise(vec3 p){
 vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){local_pos=VERTEX;}
void fragment(){
 float grain=noise(local_pos*420.0);
 float mottling=noise(local_pos*31.0);
 float pores=smoothstep(0.76,0.90,noise(local_pos*630.0));
 float earth=1.0-smoothstep(0.31,0.41,local_pos.y);
 ALBEDO=mix(vec3(0.34,0.315,0.26),vec3(0.21,0.19,0.15),earth*0.6)*(0.91+0.12*mottling+0.09*grain)-pores*0.09;
 ROUGHNESS=0.94;
}
