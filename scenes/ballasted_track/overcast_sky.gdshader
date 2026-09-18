shader_type sky;
float hash(vec2 p){p=fract(p*vec2(123.34,345.45));p+=dot(p,p+34.345);return fract(p.x*p.y);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){float n=0.0,w=0.5;for(int i=0;i<5;i++){n+=w*noise(p);p=p*2.03+vec2(8.1,3.7);w*=0.5;}return n;}
void sky(){
 float elevation=max(EYEDIR.y,0.0);
 vec2 p=EYEDIR.xz/(elevation+0.28)*2.1;
 float cloud=fbm(p);
 vec3 horizon=vec3(0.66,0.70,0.70);
 vec3 upper=mix(vec3(0.43,0.51,0.55),vec3(0.83,0.85,0.83),smoothstep(0.22,0.71,cloud));
 COLOR=mix(horizon,upper,smoothstep(0.0,0.5,elevation));
 if(EYEDIR.y<0.0){COLOR=mix(horizon,vec3(0.15,0.18,0.12),smoothstep(0.0,0.3,-EYEDIR.y));}
}