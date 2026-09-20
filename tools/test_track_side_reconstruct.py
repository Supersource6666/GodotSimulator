"""Numerical checks independent of the wheel mesh / generated ground truth."""
import unittest
import numpy as np
from track_side_reconstruct import triangulate, ridges, associate, synthesize
from PIL import Image

class ReconstructionTests(unittest.TestCase):
    def test_known_plane_and_camera_pose(self):
        angle=.37
        R=np.array([[np.cos(angle),0,np.sin(angle)],[0,1,0],[-np.sin(angle),0,np.cos(angle)]])
        t=np.array([.4,-.2,.1])
        K=np.array([[900,0,399.5],[0,920,335.5],[0,0,1]])
        camera_points=np.array([[.1,.2,1.1],[-.1,.05,1.1],[0,0,1.1]])
        world=camera_points@R.T+t
        uv=(camera_points@K.T)[:,:2]/camera_points[:,2,None]
        normal=R[:,2]
        config={'K':K.tolist(),'R_camera_to_world':R.tolist(),'t_camera_to_world_m':t.tolist(),
                'planes_world':[{'laser_id':0,'normal':normal.tolist(),'d':-float(normal@world[0])}]}
        result,valid=triangulate(uv,np.zeros(3,int),config)
        self.assertTrue(valid.all())
        np.testing.assert_allclose(result,world,atol=1e-12)
    def test_subpixel_diagonal_ridge_and_empty_image(self):
        y,x=np.indices((160,200))
        image=200*np.exp(-.5*((y-.25*x-48.3)/2.0)**2)
        mask,uv=ridges(image)
        error=np.abs(uv[:,1]-.25*uv[:,0]-48.3)/np.sqrt(1+.25**2)
        self.assertGreater(len(uv),100)
        self.assertLess(np.percentile(error,95),.08)
        self.assertEqual(len(ridges(np.zeros((60,60)))[1]),0)
    def test_ambiguous_plane_assignment_is_rejected(self):
        truth=np.array([[0,0,0],[.2,0,1],[10,0,0],[10.3,0,0],[10.6,0,0]])
        keep,ids=associate(np.array([[.1,0],[10.2,0],[50,50]]),truth)
        np.testing.assert_array_equal(keep,[False,True,False])
        self.assertEqual(ids[1],0)
    def test_defect_pair_is_reproducible(self):
        a=np.zeros((160,200),np.uint8);a[30:35,20:180]=220;a[90:95,20:180]=220
        first=synthesize(Image.fromarray(a),42,'multi')
        second=synthesize(Image.fromarray(a),42,'multi')
        for p,q in zip(first,second): np.testing.assert_array_equal(p,q)
        self.assertEqual(set(np.unique(first[2])),{0,1,2})

if __name__=='__main__': unittest.main()
