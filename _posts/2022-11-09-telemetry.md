---
title: Dataplane Telemetry
categories:
- Dataplane
feature_image: "/images/big_diesel.jpg"
---

### What is Dataplane Telemetry

I feel obligated to describe what dataplane telemetry is, because it has been central to my life for the past three years, but most of the people in my department have no idea what it is, let alone normal people in the real world. It is a field so obscure that it doesn't even have a wikipedia page and most of the first page of Google results are links to research papers or corporate datasheets. The one saving grace is that I get to play with cutting edge high end network hardware that is still months from hitting the market. The following is written mostly from my notoriously *approximate* memory, and may contain many half truths and a couple outright falsehoods, so I ask my collaborators to forgive me (sorry Chris). 

"Dataplane Telemetry Collection" refers to the process of having hardware elements within a computer network (nominally integrated in to L2 switches, though this isn't a hard rule) collect aggregate data about the packets crossing the network and report these aggregates for further analysis elsewhere, potentially informing a network operator or automated system about changing conditions in the network so they can respond (please excuse how abstract this sentence is, it was probably as painful to write as it was for you to read). The main motivation is that the data rates in modern networks far surpass what you can reasonably process in software (though that doesn't stop people), so you need to either accelerate your computations or relax your requirements. This is a way of achieving the former

To give a more concrete example, imagine you are a network operator trying to detect and mitigate DDoS attacks, and you have a network with a switch that, once a second, reports a list of every source and destination IP pair it observed, along with how many packets were sent from the source IP to the destination IP. You could detect DDoS attacks by looking for a large number of source IPs reaching out to devices in your network, and configure your router to drop traffic coming from this list of new IPs you have. Obviously many new clients connecting to a host doesn't indicate a DDoS attack, but the actual process for detecting DDoS attacks is a security research problem, and thus, not something I need to worry about (yes, this is a problem, we are working on fostering cross discipline exchanges between the networking and security teams in the UO CS department). 

From this example, you can see there is a loop consisting of four elements:
1. A piece of hardware that collects information about network traffic and sends it to a server somewhere 
2. A server running some program to try and detect anomalies and divine the health of the network from the hardware's data stream
3. An operator or program that interprets and reacts to the information the server is producing and reacts accordingly
4. Some system that can be reconfigured to respond to what the operator/control program are seeing

There is actually a secret fifth element tacked on to element 1: you need some system to control the hardware device. These devices tend to be very rudimentary and inflexible, so a lot of trickery in configuring them and parsing the results is needed to actually leverage them. In this sense, part 1 actually has a separate hardware side and software side.

![Diagram of the four elements of a complete dataplane telemetry system](/images/diagrams/four_telemetry_steps.svg)

The dream for enterprise product development people is to get all four of these elements working together and selling it as a subscription service to their clients. Researchers are not product development engineers, and each of these chunks fall under different disciplines, so I am not aware of any cohesive project that brings these four parts together. That said, each component is being worked on:
- The hardware for element 1 is being worked on by hardware companies like Broadcom (they have Broadscan) and Intel/Barefoot (they have Tofino, which is actually an FPGA but I'll gloss over that for now)
- The software for element 1 is what I specialized in
- Element 2 falls under security research, and knowledge regarding it is relatively anemic in the dataplane telemetry space. We have a set of ["canonical" programs](https://github.com/sonata-queries/sonata-queries) we need to support provided by the [Sonata](https://www.cs.princeton.edu/~jrex/papers/sonata.pdf) project, but this is more a "list of things that work well with Sonata" rather than a set of hard demands by security people, and it is limited in both scope and complexity compared to a lot of the stuff we are imagining. I don't mean to be too hard on the Sonata queries, just having a standard list to work against has been like a lighthouse popping up in the network telemetry area when we were all stuck in the fog, and suddenly we can compare our work with each other, the value of which cannot be understated. On the other hand I've spent three years becoming intimately acquainted with the shortcomings of that list and I believe that a more robust and accurate set of targets would help move the field forward. I digress.
- Element 3 is the part that probably needs to be implemented as a corporate project rather than in academia, I am aware of systems that fill a similar role (I think Fortinet has a bunch of reactive security things that auto deploy mitigations based on observed network conditions), but nothing public that we can integrate with
- Element 4 is more or less "solved" in the sense that reconfiguring routers and switches programmatically is well understood, and the industry wide move towards SDNs and reactive/intent driven SDN controllers (I'm not sure if I'm using the right terminology here, my only exposure to the space is through ONOS) provides an obvious implementation of element 4.

**Hopefully you have some sense of what dataplane telemetry is, the TLDR is that, for my purposes, it is configuring some piece of hardware to collect information about the packets crossing the network and reporting that information for further processing and analysis.**

### What do the dataplane systems look like in practice

![Diagram of the most fundamental implementation of a telemetry collection system](/images/diagrams/basic_telem_syste.svg)

There is a basic implementation of a dataplane telemetry system that everything seems to be a variant of: you have a big hash table somewhere, each time a packet arrives, some of its fields (e.g. Source IP, Destination IP, Source Port, Dest Port) are hashed to get a key to the hash table. Values from the packet (like byte count) are used to update the values for that packet's entry. This table is occasionally exported and wiped. Each row in this hash table corresponds to a *flow*, which is nominally the set of packets originating at one IP/Port combo destined for another IP/Port combo with a given protocol (a.k.a the *fivetuple*: SrcIP,DstIP,SrcPort,DstPort,Proto). The idea with the hash table is that by using these five fields as the hash key, you can have each row of the hash table correspond to a unique flow. Also note that you are free to use a subset of these keys, or include other things (think of using TCP Flags as a key so you group your packets by TCP flag). The key intuition is that you are grouping packets in to flows based on fields in the packet, and then taking aggregates over packets in a flow and reporting that.

For example, consider a telemetry system grouping by Source IP and Destination Port (i.e. it uses SrcIP and DstPort as the hash key), and tracking number of packets in data slot 1 and number of bytes in data slot 2.

Now imagine this system receives the following packets:

<style>
.tablelines table, .tablelines td, .tablelines th {
        border: 1px solid rgba(0,0,0,0.5);
        }
</style>

|---|---|---|---|---|---|---|
|Packet|SrcIP|DstIP|SrcPort|DstPort|Protocol|SizeInBytes|
|---|---|---|---|---|---|---|
|Pkt1|1.2.3.4|10.0.2.5|80|54321|6|1500|
|Pkt2|6.7.8.9|10.1.32.128|23232|22|6|96|
|Pkt3|1.2.3.4|10.0.2.5|80|54321|6|1500|
|Pkt4|1.2.3.4|10.0.2.5|80|54321|6|451|
|Pkt5|6.7.8.9|10.1.5.25|33333|22|6|104|
|---|---|---|---|---|---|---|
{: .tablelines}

After running these through the telemetry system with the hypothetical configuration described above, the contents of the hash table would look like:

|---|---|---|
|Key|Data 1 (Packet Count)|Data 2 (Byte Count)|
|---|---|---|
|1.2.3.4,54321|3|3451|
|6.7.8.9,22|2|200|
|---|---|---|
{: .tablelines}

Hopefully this simple example illustrates the value of having some system capable of taking packet data at line speed and aggregating it down to something much more manageable for the backend, which becomes extremely valuable as your line speed starts being measured in terabits per second and you start to get thousands of packets per second for each flow. This is a very elementary example, more robust systems can apply operations like min, max, average and many others; as well as extract more complex values from packets like TTL or inter packet times to use as operands. This opens up a whole world of possibility for what you can track efficiently.


The dataplane telemetry system I have worked most extensively with is *Broadscan* by Broadcom. I have signed a very brutal NDA protecting anything technical about Broadscan, and engineers at Broadcom have been kind enough to share some of their most protected documentation with us and I don't want to make them regret that. As such in the future I will only describe Broadcom in the vaguest terms outside out things they have already approved us revealing in our previous publications.

If you want to see some implementations, [Newton](https://chensun-me.github.io/papers/newton-conext20.pdf) implements a lot of what I described with a fancy framework around it (see figure 2 in particular), and I have a P4 implementation of a functionally similar but architecturally very different system available [here](https://github.com/waltoconnor/p4_concurrent_telemetry_switch)

 (if you don't know what P4 is, it is an FPGA language like VHDL designed to allow easy implementation of network devices. Critically P4 programs are not software, but programmatic specifications of hardware, and a device "running" a P4 program actually has its internal circuitry reconfigured to become the hardware device specified in the P4 program) 

### What alternatives are there  
 Dataplane telemetry does not exist in a vacuum, there is a larger network telemetry field that gets lots of money poured in to it because it helps solve real problems for large network operators. I am not all that well acquainted with the rest of the Network telemetry field, so most of what I'm about to write is based off partial recollections of discussions I had with my collaborator Chris Misa (who is much more knowledgeable about, and better at articulating these things). 
 My understanding is that there is an old generation of developed telemetry products like [Zeek](https://zeek.org/), where you just mirror all your packets in to a cluster of servers, and their CPUs crunch the numbers and report back. The thing is that the first pass these systems make is typically to group the packets in to flows by putting them in a big hash table, and a large chunk of the processing time (potentially the majority, I haven't evaluated it) is spent just inserting packets in to a hash table. 
 There is also a set of three "second generation" approaches (probably more by now), and all of them share the same basic premise: group packets in to flows with a big hash table *but faster*, and then dump this hash table on to something else for further processing. The logic here is that most flows have dozens to thousands of packets per second, so if you deliver flows instead of packets, you end up needing to process a few orders of magnitude less data, which (for the time being) does scale. 
 - The first "second generation approach" is Dataplane Telemetry: to use some piece of hardware sitting in the network (either an ASIC like Broadscan or an FPGA programmed to do the telemetry like some of the P4 systems) to implement the hash table that groups packets in to flows and then export that over the network for further processing. 
 - The second approach is to just jam everything on the GPU. This was problematic before as you still needed the CPU to decode the packet in the kernel and then pass it to the GPU for processing, so you still were bottlenecked by the CPU. The Nvidia bought Mellanox and set up a way to access the NIC from the GPU via RDMA, which basically solved this problem. I am unsure of where the research space is relative to this, but I know that solution exists. This approach tends to be the most expensive hardware wise (at least with GPUs priced the way they were while I was working), but is also much more flexible than the ASIC approaches, and is lower risk from a corporate perspective as most places dealing with large amounts of data are going to have other things they can task their GPUs and associated servers with if the network telemetry thing doesn't pan out.
 - The third approach is to use approximations, namely sketches. Sketching diverges from the normal hash table approach somewhat that it uses what is basically very fancy stacked bloom filters on the dataplane side (which is normally implemented either in P4 or in software), and then uses extremely complicated math on the backend to basically recover the `n` largest flows on the backend (it's a lot more complex than that, but that's the best high level premise I can give. See [sketchlearn](https://conferences.sigcomm.org/events/apnet2018/papers/sketchlearn.pdf) for a complete implementation). The premise here is that you *probably* don't need to perfectly track *all* the flows, you really just want to know how many unique flows you have, some information about the distributions of the data you are tracking across all the flows, and then maybe your top 10%-1% largest flows. If you can structure whatever program is using the data to be content with the numbers the sketch system delivers, you can make the amount of data shipped from the dataplane to the backend constant regardless of traffic volume (in theory), though now you compromise on accuracy instead of volume of data exported. In practice we found that the sketch systems were inflexible in the face of changing traffic dynamics, and have some other serious issues that we will probably discuss in later papers, but the implementation is extremely interesting and they are so clever that I can't be too hard on them. Also note that certain implementations of sketching can be considered dataplane telemetry (if the sketches are done in a P4 switch, it's telemetry, in the dataplane), but it's not ***my*** dataplane telemetry so I put it in a different category.

 Interestingly, all three approaches seem to be competitive with each other (as long you stay in the sphere of things that sketches are good at), and there is a lot of room for large players like Nvidia, Broadcom, and Intel/Barefoot to build a really killer product out of their bread and butter tech. The thing it, it doesn't matter how good the implementations and tech is if you don't have anything to do with it, and the "killer app" of telemetry that solves a very real concern of network operators in a really convincing way--one that forces everyone to upgrade to the latest and greatest as a matter of best practice--hasn't materialized yet. Maybe it has and I just don't know about it. Maybe it was the Sonata task list and I just haven't caught up yet. My main takeaway from three years in research is that I have no idea what is going on, but that's ok because almost no one does.


###### Photo Description
 This is picture I took of an absolutely gorgeous Ingersoll Rand diesel engine in the Yankee Fork gold dredge in Idaho. These were connected to a small generator and a large self exciting alternator, during startup the generator would "prime" the magnetic field in the alternator, which would then take over and power the rest of the facility as it dragged itself around the gorge vacuuming up gold. The diesel that powered these was purchased in the 30s and 40s at the price of $0.0002/gallon.