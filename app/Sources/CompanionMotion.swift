import Foundation

/// Continuous simulation: activity changes set targets; pose weights, heading and
/// velocity ease toward those targets. Whole-body pixel poses follow distance-driven gait phase.
struct CompanionMotion: Equatable {
    enum Activity: String, CaseIterable { case idle, walk, look, groom, play, jump, sleep, stretch }
    var x = 0.5
    var destination = 0.5
    var facing = 1.0
    var heading = 0.0
    var activity: Activity = .idle
    var previousActivity: Activity = .idle
    var elapsed = 0.0
    var duration = 3.0
    var travelDistance = 0.0
    var velocity = 0.0
    var gait = 0.0
    var total = 0.0
    var jumpHeight = 0.0
    var weights: [Activity:Double] = [.idle:1]
    private var randomState: UInt64
    private var wasResting = false
    init(seed: UInt64 = 7919) { randomState = seed == 0 ? 7919 : seed }
    mutating func random() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / 9007199254740992
    }
    func weight(_ activity: Activity) -> Double { weights[activity] ?? 0 }
    mutating func advance(_ delta: Double, animal: String, resting: Bool, reducedMotion: Bool = false, visible: Bool = true) {
        guard visible else { return }
        let dt=min(0.1,max(0,delta.isFinite ? delta : 0))
        if reducedMotion {
            activity=resting ? .sleep : .idle;weights=[activity:1];wasResting=resting;jumpHeight=0;velocity=0
            return
        }
        if resting && !wasResting { transition(.sleep,duration:20) }
        if !resting && wasResting { transition(.stretch,duration:2.4) }
        wasResting=resting;total+=dt;elapsed+=dt
        let response=1-exp(-dt*(activity == .sleep || weight(.sleep)>0.12 ? 2.8:7))
        for kind in Activity.allCases { weights[kind]=weight(kind)+((activity==kind ? 1.0:0)-weight(kind))*response }
        let jumpTarget=activity == .jump ? max(0,sin(min(1,elapsed/max(0.1,duration))*Double.pi)):0
        jumpHeight += (jumpTarget-jumpHeight)*(1-exp(-dt*10))
        let targetHeading=facing>0 ? 0.0:Double.pi
        heading += (targetHeading-heading)*(1-exp(-dt*9))
        let speed=animal=="Cow" ? 0.10 : animal=="Rabbit" ? 0.20:0.14
        let distance=destination-x
        let desiredFacing=distance>=0 ? 1.0:-1.0
        let walking=activity == .walk && !resting
        // Brake before reversing; never squash the entire animal through a turn.
        let reversing=walking && desiredFacing != facing
        if reversing && abs(velocity)<0.002 {facing=desiredFacing}
        let targetVelocity=walking && desiredFacing==facing ? facing*speed*min(1,abs(distance)/0.055)*weight(.walk):0
        velocity += (targetVelocity-velocity)*(1-exp(-dt*8))
        if abs(velocity)<0.00005 {velocity=0}
        let priorX=x
        x += velocity*dt
        if walking && abs(distance)<0.003 && abs(velocity)<0.005 {transition(.look,duration:1.3+random()*2.5)}
        let stride=animal=="Cow" ? 0.10:animal=="Rabbit" ? 0.12:0.096
        travelDistance += abs(x-priorX)
        gait += abs(x-priorX)/stride*2 * .pi
        x=min(0.88,max(0.12,x))
        if !resting && elapsed>=duration { choose(animal) }
    }
    private mutating func transition(_ next:Activity,duration:Double) {
        previousActivity=activity;activity=next;elapsed=0;self.duration=duration
    }
    private mutating func choose(_ animal:String) {
        let roll=random()
        let next:Activity
        if roll<0.36 { next = .walk }
        else if roll<0.52 { next = .idle }
        else if roll<0.64 { next = .look }
        else if roll<0.75 { next = animal=="Cow" ? .look:.groom }
        else if roll<0.84 { next = .stretch }
        else if roll<0.88 { next = .play }
        else if roll<0.94 { next = animal=="Cow" ? .play:.jump }
        else { next = .sleep }
        transition(next,duration:next == .sleep ? 7+random()*11:2+random()*4)
        if next == .walk {
            destination=0.12+random()*0.76
            if abs(destination-x)<0.18 { destination=x<0.5 ? 0.83:0.17 }
            duration=20
        }
    }
    mutating func play() { if !wasResting { transition(.play,duration:3.2) } }
    var jump:Double { jumpHeight }
    var sleeping:Bool { activity == .sleep }
}
