import Foundation
@testable import DockGrove

func runCompanionMotionTests() {
    let names=["Miso","Black cat","Orange cat","Golden dog","Husky","Dragon","Cow","Rabbit","Fox"]
    for (i,name) in names.enumerated() {
        var a=CompanionMotion(seed:UInt64(i+71)),b=a
        var activities=Set<String>(), phases=Set<Int>(),minX=1.0,maxX=0.0
        for _ in 0..<18000 {
            let prior=a
            a.advance(1.0/60,animal:name,resting:false);b.advance(1.0/60,animal:name,resting:false)
            precondition(abs(a.x-prior.x)<0.004 && abs(a.heading-prior.heading)<0.45)
            precondition(abs(a.velocity-prior.velocity)<0.03,"Acceleration must ease")
            if a.facing != prior.facing {precondition(abs(prior.velocity)<0.002,"Turn only after braking")}
            if abs(a.x-prior.x)<0.00000001 {precondition(abs(a.gait-prior.gait)<0.00001,"Stationary feet must not cycle")}
            for kind in CompanionMotion.Activity.allCases { precondition(abs(a.weight(kind)-prior.weight(kind))<0.12) }
            precondition(a==b,"Motion must be reproducible for review")
            precondition(a.x>=0.12 && a.x<=0.88 && a.x.isFinite)
            activities.insert(a.activity.rawValue);minX=min(minX,a.x);maxX=max(maxX,a.x)
            if a.activity == .walk { phases.insert(Int((a.gait.truncatingRemainder(dividingBy:2 * .pi))*100)) }
        }
        precondition(activities.contains("walk") && activities.contains("sleep") && activities.contains("stretch") && activities.contains("look") && activities.contains("play"))
        precondition(phases.count>500 && maxX-minX>0.4,"Each animal needs distance-driven locomotion and space to roam")
        a.play();precondition(a.activity == .play)
        let paused=a;a.advance(1000,animal:name,resting:false,visible:false);precondition(a==paused)
        for _ in 0..<100 { a.advance(1,animal:name,resting:true);precondition(a.activity == .sleep) }
        a.advance(0,animal:name,resting:false);precondition(a.activity == .stretch)
        a.advance(0,animal:name,resting:false,reducedMotion:true);let still=a
        a.advance(4,animal:name,resting:false,reducedMotion:true);precondition(a==still)
        a.advance(.nan,animal:name,resting:false);precondition(a.x.isFinite)
    }
    print("PASS: nine deterministic autonomous companions, continuous locomotion and eased pose transitions, bounds, varied activities, hidden pause, manual rest and Reduce Motion")
}
