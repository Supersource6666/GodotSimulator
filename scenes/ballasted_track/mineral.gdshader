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
 // Irregular aggregate cells keep the formation continuous between detail stones.
 vec2 cell=world.xz*19.0;
 vec2 base=floor(cell);
 float nearest=2.0;
 float second=2.0;
 float mineral=0.0;
 for(int x=-1;x<=1;x++){
  for(int y=-1;y<=1;y++){
   vec2 id=base+vec2(float(x),float(y));
   vec2 offset=vec2(hash(vec3(id,1.0)),hash(vec3(id,7.0)));
   float dist=length(id+offset-cell);
   if(dist<nearest){second=nearest;nearest=dist;mineral=hash(vec3(id,13.0));}
   else{second=min(second,dist);}
  }
 }
 float crevice=smoothstep(0.015,0.12,second-nearest);
 vec3 aggregate=mix(vec3(0.76,0.73,0.66),vec3(1.12,1.11,1.05),mineral);
 ALBEDO=stone_color.rgb*tint.rgb*aggregate*(0.55+0.45*crevice)*(0.83+0.25*grain);
 ROUGHNESS=0.94;
 NORMAL=normalize(NORMAL-vec3(dFdx(grain),dFdy(grain),0)*0.18);
}
