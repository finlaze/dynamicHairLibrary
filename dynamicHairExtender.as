package dynamicHairLibrary {

	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.display.DisplayObject;
	import flash.geom.Matrix;
	import flash.display.DisplayObjectContainer;
	import flash.utils.Dictionary;
	import SDTMods.*;
	import flash.geom.Point;
	import flash.geom.ColorTransform;
	import flash.events.Event;
	import fl.motion.MatrixTransformer;

	//dynamicHairExtender by stuntcock

	public dynamic class dynamicHairExtender extends flash.display.MovieClip {	
		const modName:String = "dynamicHairExtender";
		const modCreator:String = "stuntcock";
		const modVersion:Number = 5.6;
		// The following are basic variables which will store fundamental pointers.
		// They provide us with a "gateway" into SDT data.
		var main;
		var g;
		// We maintain a temporary collection of links which have been flagged for sharing between Hair Ropes
		var sharedLinks:Dictionary;
		var sharedRopes:Dictionary;
		var wrappedMethod:Function;
		// Modders can designate a hair segment for sharing by naming it with a special prefix
		// Modders can designate a hair segment to influence other strands (even if they haven't been designated for sharing) by naming it with a special prefix
		const sharedSegmentPrefix:String = "SHARED_";
		const forcedSegmentPrefix:String = "FORCED_";
		const ModTypes_LEASH:String = "LEASH";
		const DEFAULT_ROTATION_BLENDING:Number = 0.0;
		const DEFAULT_ELASTICITY_PROXIMAL:Number = 0.25;
		const DEFAULT_ELASTICITY_DISTAL:Number = 0.825;
		const ELASTICITY_MINIMUM:Number = 0.0;
		const ELASTICITY_MAXIMUM:Number = 5.0;
		const INFLUENCE_MINIMUM:Number = 0.0;
		const INFLUENCE_MAXIMUM:Number = 1.0;
		// Maintain a local reference to the lProxy class so that we can easily register PRE and POST methods
		var lProxy:Class;
		var Rope:Class;
		var RopeLink:Class;
		var AlphaRGBObject:Class;
		var CharacterElementHelper:Class;
		var LoadedMod:Class;
		var CharacterControl:Class;
		var i:int;

		public function initl(l)			//boiler plate setup for getting settings started, put startup stuff here that are not dependent on loaded settings
		{
			// Initialize the standard "reference" variables
			main = l;
			g = l.g;
			
			// Check whether a newer (or equal) version is already loaded
			if (((l[modName] as Object) != null) && (((l[modName] as Object).modVersion as Number) || 0.0) < this.modVersion) {
				// Unload the previous version of the mod
				try { l[modName].doUnload(); } catch (myError:Error) { }
			}
			if ((l[modName] as Object) != null) {
				// An equal-or-greater version of the mod is already loaded.  Do nothing.
				return;
			} else {
				// Load this version of the mod
				// Just fall-through to the code below
			}

			// Apply default values to the configuration parameters

			// Initialize local variables
			sharedLinks = new Dictionary();
			sharedRopes = new Dictionary();
			lProxy = main.getLoaderClass("Modules.lProxy");
			Rope = main.eDOM.getDefinition("obj.Rope") as Class;
			RopeLink = main.eDOM.getDefinition("obj.RopeLink") as Class;
			LoadedMod = main.eDOM.getDefinition("obj.LoadedMod") as Class;
			AlphaRGBObject = main.eDOM.getDefinition("obj.AlphaRGBObject") as Class;
			CharacterElementHelper = main.eDOM.getDefinition("obj.CharacterElementHelper") as Class;
			CharacterControl = main.eDOM.getDefinition("obj.CharacterControl") as Class;
			
			// Boilerplate
			finishinit();
			main.updateStatusCol(modName + " v" + modVersion + " done loading","#00ff00");
		}

		function finishinit()		//put startup stuff here that require loaded settings
		{
			// Proxy the RGB-shifting code in CharacterControl to fix a small (but fatal) bug in the tryToSetFillChildren function
			var bugfixProxy = (lProxy as Class).checkProxied((CharacterControl as Class), "tryToSetFillChildren");
			if (bugfixProxy) { bugfixProxy.removePre(tryToSetFillChildren_Fixed); }
			var tryToSetFillChildren = (lProxy as Class).createProxy(CharacterControl, "tryToSetFillChildren");
			tryToSetFillChildren.addPre(tryToSetFillChildren_Fixed, true);
			tryToSetFillChildren.hooked = false;
			
			// The erroneous function is duplicated in the CharacterElementHelper class.  I'm -reasonably- certain that it doesn't get
			// invoked normally, but we'll apply the fix just to be safe.
			var cc = g.characterControl;	
			var characterElementHelpers:Array = [cc.collarControl, cc.gagControl, cc.cuffsControl, cc.ankleCuffsControl, cc.eyewearControl, cc.pantiesControl,
				cc.armwearControl, cc.legwearControl, cc.legwearBControl, cc.bottomsControl, cc.footwearControl, cc.topControl, cc.braControl, cc.tonguePiercingControl, 
				cc.nipplePiercingControl, cc.bellyPiercingControl, cc.earringControl, cc.headwearControl];
			characterElementHelpers.forEach(function(helper:Object, ...args):void {
				helper["tryToSetFillChildren"] = CharacterControl["tryToSetFillChildren"];
			});

			// Proxy the breast-size method to resolve an intermittent bug in which RGB settings are lost during size changes
			var setBreastCostumeSize_Post = dynamicHairLibrary.dynamicHairExtender.methodWrapper(applyBreastCostumeRGB, cc);
			var setBreastCostumeSize = (lProxy as Class).checkProxied(cc, "setBreastCostumeSize");
			if (setBreastCostumeSize) { setBreastCostumeSize.restoreProxy(true); }
			setBreastCostumeSize = (lProxy as Class).createProxy(cc, "setBreastCostumeSize");
			setBreastCostumeSize.addPost(setBreastCostumeSize_Post, true);
			
			// Proxy the Dynamic Hair registration function so that we can add non-standard parameters
			try {
				var addDynamicHairMod = (lProxy as Class).createProxy(g.customElementLoader, "addDynamicHairMod");
				addDynamicHairMod.addPre(addDynamicHairMod_Pre, true);
				main[modName] = this;
			} catch (myError:Error) {
				main.updateStatusCol("dynamicHairExtender Loading Error: " + myError.toString(),"#FF0000"); 
			}
			
			// Add prototype functions
			
			// Add a special movement function to all of the RopeLink elements
			RopeLink.prototype.moveInfluenced = function(vector:Point, influence:Number, maximumY:Number = Number.MAX_VALUE):void {
				this.lastPos.x = this.x;		// This is legacy code.  lastPos is never used, but we'll include it just-in-case.
				this.lastPos.y = this.y;		// This is legacy code.  lastPos is never used, but we'll include it just-in-case.
				
				// Apply the vector
				(this as Point).offset(vector.x * influence, vector.y * influence);
				
				// Enforce the y-axis maximum value (if specified)
				this.y = Math.min(this.y, maximumY);
			}
			
			// vvv The stuff below is boilerplate for SDT mods vvv
			main.unloadMod();
			main.registerUnloadFunction(doUnload);
		}
		
		static function tryToSetFillChildren_Fixed (targetElement:MovieClip, targetName:String, ct:ColorTransform) {
			if (targetElement.fillOverrides as Dictionary) { targetName = (targetElement.fillOverrides as Dictionary)[targetName] || targetName; }
			for (var i:uint = 0; i < targetElement.numChildren; i++) {
				if(targetElement.getChildAt(i).name == targetName)
				{
				   targetElement.getChildAt(i).transform.colorTransform = ct;
				}
				if(targetElement.getChildAt(i) is MovieClip)
				{
				   tryToSetFillChildren_Fixed(targetElement.getChildAt(i) as MovieClip,targetName,ct);
				}
			}
		}
		
		static function applyBreastCostumeRGB(cc:Object):void {
			cc.braControl.fillFunction(cc.braControl.rgb1, "rgbFill");
			if (cc.braControl.rgb2) { cc.braControl.fillFunction(cc.braControl.rgb2, "rgbFill2"); }
			cc.topControl.fillFunction(cc.topControl.rgb1, "rgbFill");
			if (cc.topControl.rgb2) { cc.topControl.fillFunction(cc.braControl.rgb2, "rgbFill2"); }
		}

		// This entire function is copy-pasted from SDT decompilation.  It should not be modified unless you know
		// exactly what you're doing.  It contains one new section, which is marked with comments.
		function addDynamicHairMod_Pre(hairModParameters:*) {
			try {
				if ((hairModParameters.modTypeReplacer as String) != null) { hairModParameters.modType = hairModParameters.modTypeReplacer; }
				var hairParent:DisplayObjectContainer = null;
				var helper = g.customElementLoader.modTargetHelpers[hairModParameters.targetElement || hairModParameters.modType];
				if (hairModParameters.targetElement == null) { return; }
				hairParent = helper.targetDictionary["target"];
				if(hairModParameters.overwrite) {
					// Clear the link-sharing collection.  New Ropes do not share with anything which preceded the Overwrite.
					sharedLinks = new Dictionary();
					sharedRopes = new Dictionary();
					
					// Remove any existing mods which share the type of the incoming mod
					switch (hairModParameters.modType) {
						case ModTypes.DYNAMIC_HAIR:
							g.customElementLoader.clearModTypes([ModTypes.DYNAMIC_HAIR]);
							g.customElementLoader.clearModTypes([ModTypes.HAIR_COSTUME]);
							break;
						case ModTypes_LEASH:
							g.customElementLoader.clearModTypes([ModTypes_LEASH]);
							break;
						default:
							g.customElementLoader.clearModTypes([hairModParameters.modType]);
							break;
					}
				}

				var customGravityAngle:Number = 0;
				if(hairModParameters.gravityAngle) {
					customGravityAngle = Number(hairModParameters.gravityAngle);
				}

				var anchorContainer:DisplayObjectContainer = null;
				if ((hairModParameters.anchorContainer as String) != null) {
					try { 
						anchorContainer = findObjectByPath(g, hairModParameters.anchorContainer) as DisplayObjectContainer; 
						if (anchorContainer == null) { 
							main.updateStatusCol("dynamicHairExtender Loading Error: anchorContainer '" + hairModParameters.anchorContainer + "' was not recognized.  If this is a custom prop, please ensure that it's on-stage before loading the Dynamic Hair object.", "#FF0000"); 
						}
					} catch (myError:Error) {}
				}

				if ((hairModParameters.visualParent as String) != null) {
					var visualParent:DisplayObjectContainer;
					try { 
						visualParent = (findObjectByPath(g, hairModParameters.visualParent) as DisplayObjectContainer); 
					} catch (myError:Error) {
					} finally {
						if (visualParent == null) { 
							main.updateStatusCol("dynamicHairExtender Loading Error: visualParent '" + hairModParameters.visualParent + "' was not recognized.  If this is a custom prop, please ensure that it's on-stage before loading the Dynamic Hair object.", "#FF0000"); 
						}
						hairParent = visualParent || hairParent;
					}
				}

				var dynamicHairRope = new Rope(hairModParameters,hairParent,null,anchorContainer,customGravityAngle);

				if(!(hairModParameters.toggleable == undefined) && !hairModParameters.toggleable) {
					dynamicHairRope.makeUnToggleable();
				}

				if ((hairModParameters.visualChildIndex as int) != undefined) {
					hairParent.setChildIndex(dynamicHairRope, (hairModParameters.visualChildIndex as int));
				}
				if ((hairModParameters.segmentVisualIndex as Dictionary) != undefined) {
					for (var seg:* in (hairModParameters.segmentVisualIndex as Dictionary)) {
						try {
							var childSegment:DisplayObject;
							if ((seg as String) != undefined) {
								// Assume it's a segment name
								childSegment = (dynamicHairRope.ropeGraphic as MovieClip).getChildByName(seg as String);
							} else if ((seg as int) != undefined) {
								// Assume it's a segment index
								childSegment = (dynamicHairRope.ropeGraphic as MovieClip).getChildAt(seg);
							} else { continue; }
							// Apply the desired visual index (z-order) value
							(dynamicHairRope.ropeGraphic as MovieClip).setChildIndex(childSegment, (hairModParameters.segmentVisualIndex[seg] as int));
						} catch (myError:Error) { }
					}
				}
// TODO: maskPath was an abortive attempt at supporting ThighMaster functionality.  Maybe remove it since it's been superceded?
				if ((hairModParameters.maskPath as String) != null) {
					try {
						dynamicHairRope.mask = findObjectByPath(g, hairModParameters.maskPath);
						(dynamicHairRope.mask as MovieClip).visible = true;
 					} catch (myError:Error) { }
				}
				dynamicHairRope.rotationBlending = DEFAULT_ROTATION_BLENDING;
				if ((hairModParameters.rotationBlending as Number) != undefined) {
					dynamicHairRope.rotationBlending = hairModParameters.rotationBlending;
				}
				
				// Skin-colour variation is implemented by including multiple Keyframes in the Flash object.
				// Unforunately, Dynamic Hair elements are inherently loaded as MovieClip objects, which means that they'll begin
				// animating as soon as they hit the stage.  This causes them to rapidly and continuously flicker through the 
				// available skin colours.
				// As a countermeasure, we allow modders to specify "autoPlay = false" on Segments (or the whole Rope).
				if(((hairModParameters.autoPlay as Boolean) == false) || ((hairModParameters.autoPlay as Dictionary) != undefined)){
					for (i = 0; i < dynamicHairRope.segments.length; i++) {
						if(((hairModParameters.autoPlay as Boolean) == false) || (((hairModParameters.autoPlay as Dictionary)[i] as Boolean) == false)) {
							(dynamicHairRope.segments[i] as MovieClip).stop();
						}
					}
				}
				
				// Apply custom elasticity rules
				if ((hairModParameters.distalElasticityFactors as Dictionary) != undefined) {
					 dynamicHairRope.distalElasticityFactors = hairModParameters.distalElasticityFactors;
				}
				if ((hairModParameters.proximalElasticityFactors as Dictionary) != undefined) {
					 dynamicHairRope.proximalElasticityFactors = hairModParameters.proximalElasticityFactors;
				}
				if ((hairModParameters.allowElongations as Dictionary) != undefined) {
					dynamicHairRope.allowElongations = hairModParameters.allowElongations;
				}
				if ((hairModParameters.allowCompressions as Dictionary) != undefined) {
					dynamicHairRope.allowCompressions = hairModParameters.allowCompressions;
				}
							
				// Apply custom gravity parameter (for compatibility with scene-gravity shifting in the Animtool mod)
				if(hairModParameters.gravityAngle) {
					// Note: this is a write-once custom variable.  It will never be read by the SDT physics engine,
					// nor by the dynamicHairExtender mod.  It exists solely for the benefit of animtools -- 
					// when animtools needs to rotate the whole scene, it can set an appropriate gOffset value
					// for every hair strand (  gOffset = gOffsetCustom + sceneGravity;  )
					dynamicHairRope.gOffsetCustom = Number(hairModParameters.gravityAngle);
				}
			
// TODO: orientationSource is kinda deprecated and has never been very useful.  Maybe we should remove it to reduce the risk of confusion?
				// Register the special static-anatomy link
				// Default case: hair elements will draw Static orientation from [g.her] -- the girl element
				if ((hairModParameters.orientationSource as String) != undefined) {
					try {
						dynamicHairRope.orientationSource = findObjectByPath(g, hairModParameters.orientationSource);
						if ((dynamicHairRope.orientationSource as DisplayObject) == null) { 
							main.updateStatusCol("dynamicHairExtender Loading Error: orientationSource '" + hairModParameters.orientationSource + "' was not recognized.  If this is a custom prop, please ensure that it's on-stage before loading the Dynamic Hair object.", "#FF0000"); 
						}
					} catch (myError:Error) { }
				}
				dynamicHairRope.orientationSource = dynamicHairRope.orientationSource || g.her;

				// Deal with any Shared elements
				// The basic strategy is to iterate through all of the Segments of this rope, checking for the presence of a
				// special prefix in the MovieClip names (as specified by the modder in Flash).  Where a match is found, we 
				// either register the corresponding Link into a lookup table (if new), or replace it entirely with the Link
				// from the lookup table (if it's already been registered).
				var segmentsAndRope:Array = (dynamicHairRope.segments as Array).slice(); segmentsAndRope.push(dynamicHairRope.ropeGraphic);
				dynamicHairRope.sharedRopes = new Dictionary();		// Initialize the Dictionary if it does not yet exist
				// Special case: the anchor Link can also be shared.  In that case, the modder must put the prefix onto the 
				// hair-strand object (as it appears on Main).  This name can then be invoked by segments in other strands
				// (or by other segments WITHIN that strand, but that's unusual).
				for each (var segment:DisplayObject in segmentsAndRope) {
					if (segment.name != null) {
						var prefixEnd:int = segment.name.indexOf(sharedSegmentPrefix);
						if (prefixEnd == -1) { continue; }

						// We've found a shared segment.  Is it new?
						var segmentIndex:int = (dynamicHairRope.segments as Array).indexOf(segment);
						// Note: segmentIndex will be -1 if this isn't actually a segment (because we've matched the Rope name).
						if (sharedLinks[segment.name] == undefined) {
							// Assert: it's new.

							// Lookup the distal Link belonging to this Segment, and then register it.
							sharedLinks[segment.name] = (dynamicHairRope.links as Array)[segmentIndex + 1];
							sharedLinks[segment.name].parentRope = dynamicHairRope.ropeGraphic.name;
							this.sharedRopes[dynamicHairRope.ropeGraphic.name] = dynamicHairRope;
						} else {
							// Assert: it's already registered.

							// Splice in the already-registered Link.
							(dynamicHairRope.links as Array).splice(segmentIndex + 1, 1, sharedLinks[segment.name]);
							// Register the sharing relationship so that the two Ropes can lookup each other at runtime
							dynamicHairRope.sharedRopes[sharedLinks[segment.name].parentRope] = this.sharedRopes[sharedLinks[segment.name].parentRope];
							this.sharedRopes[sharedLinks[segment.name].parentRope].sharedRopes[dynamicHairRope.name] = dynamicHairRope;
						}
					}
				}
				
				if ((hairModParameters.linkWeights as Dictionary) != undefined) {
					try {
						// Replace Segment names with link indices
						hairModParameters.linkWeights = convertSegmentNamesToLinkIndices(hairModParameters.linkWeights, dynamicHairRope);
						
						// Apply the configuration parameters to the object
						for (i = 0; i < dynamicHairRope.links.length; i++){
							if ((hairModParameters.linkWeights[i] as Number) != undefined) {
								dynamicHairRope.links[i].mass = hairModParameters.linkWeights[i];
							}
						}
					}
					catch (myError:Error) { }
				}
				
				// Reverse the Z-order of segments (if requested)
				if (((hairModParameters.reverseSegmentOrder as Boolean) != undefined) && hairModParameters.reverseSegmentOrder) {
					//for (i = 0; i < dynamicHairRope.segments.length; i++){
					for (i = dynamicHairRope.segments.length - 1; i >= 0; i--){
						dynamicHairRope.ropeGraphic.setChildIndex(dynamicHairRope.segments[i],0);
					}
				}
								
				// Sanitize the configuration parameters
				if ( (hairModParameters.simCyclesPerUpdate == null) || (hairModParameters.simCyclesPerUpdate as int) < 0) {
					hairModParameters.simCyclesPerUpdate = 1;
				}
				dynamicHairRope.simCyclesPerUpdate = hairModParameters.simCyclesPerUpdate;
				if ( (hairModParameters.maxCyclesPerUpdate == null) || (hairModParameters.maxCyclesPerUpdate as int) < 0) {
					hairModParameters.maxCyclesPerUpdate = int.MAX_VALUE;
				}
				dynamicHairRope.maxCyclesPerUpdate = hairModParameters.maxCyclesPerUpdate;

				if ((hairModParameters.slavedUpdates as Boolean) == undefined) {
					hairModParameters.slavedUpdates = false;
				}
				dynamicHairRope.slavedUpdates = hairModParameters.slavedUpdates;
				if ((hairModParameters.doNotSimulate as Boolean) == undefined) {
					hairModParameters.doNotSimulate = false;
				}
				dynamicHairRope.doNotSimulate = hairModParameters.doNotSimulate;
				if ((hairModParameters.anchored as Boolean) == undefined) {
					hairModParameters.anchored = true;
				}
				dynamicHairRope.anchored = hairModParameters.anchored;
				
				
				// Next, we must deal with the primary physics function: rope.Move
				
				// The rope.Move method is invoked by an event handler, and is therefore unproxyable.  Remove and replace it.
				dynamicHairRope.removeEventListener(Event.ENTER_FRAME, dynamicHairRope.move);
				dynamicHairRope.physicsStep = function() { physicsStep(dynamicHairRope); }
				dynamicHairRope.enterFrame = methodWrapper(function(rope:Object):void {
					try {
						for (var physicsCounter:uint = 0; physicsCounter < rope.simCyclesPerUpdate; physicsCounter++) {
							// If there are any subsidiary/slaved ropes, simulate them now
							for (var physicsSlave:* in (rope.sharedRopes as Dictionary)) {
								if ((rope.slavedUpdates as Boolean) == false && (rope.sharedRopes[physicsSlave].slavedUpdates as Boolean) == true && (rope.sharedRopes[physicsSlave].doNotSimulate as Boolean) == false) {
									if (physicsCounter >= (rope.sharedRopes[physicsSlave] as Rope).maxCyclesPerUpdate) {
										// This rope has already been simulated enough; don't do any more.
										continue;
									}
									(rope.sharedRopes[physicsSlave] as Rope).physicsStep((rope.sharedRopes[physicsSlave] as Rope));
								}
							}
							// Perform the appropriate number of physics simulation cycles (0 ... n, but typically 1)
							physicsStep(rope);
						}
						
						// Draw the rope's segments in their new (physics-determined) shapes and sizes
						rope.updateRopeGraphic();
						// If there are any subsidiary/slaved ropes, draw them now
						for (var graphicsSlave:* in (rope.sharedRopes as Dictionary)) {
							if ((rope.slavedUpdates as Boolean) == false && (rope.sharedRopes[graphicsSlave].slavedUpdates as Boolean) == true) {
								(rope.sharedRopes[graphicsSlave] as Rope).updateRopeGraphic();
							}
						}
					} catch (myError:Error) { main.updateStatusCol(myError,"#FF0000"); } 
				}, dynamicHairRope);
				// Note that the removal is common, but the replacement occurs only for independent Rope objects.
				// A slaved Rope does _not_ react to the ENTER_FRAME event; it relies on its master Rope to invoke functions when appropriate.
				if (!dynamicHairRope.slavedUpdates) {  dynamicHairRope.addEventListener(Event.ENTER_FRAME, dynamicHairRope.enterFrame, false, 0, true); }
				
				// Finally: setup a proxy so that we can catch the Kill invocation and properly detach our new event listener
				var killRope = (lProxy as Class).createProxy(dynamicHairRope, "kill");
				killRope.hooked = true;		// The original method is harmless (redundant removeEventListener calls are allowed) so we'll leave it hooked for thoroughness
				wrappedMethod = methodWrapper(detachFrameEventListener, dynamicHairRope);
				killRope.addPre(wrappedMethod, true);

				// Register the influence (aka trust) rules for this Rope
				if ((hairModParameters.sharedLinkInfluences as Dictionary) != undefined) {
					dynamicHairRope.sharedLinkInfluences = convertSegmentNamesToLinkIndices(hairModParameters.sharedLinkInfluences, dynamicHairRope);
				}
				
				// Register the rotation rules for this Rope
				if ((hairModParameters.relativeRotationMultipliers as Dictionary) != undefined) {
					dynamicHairRope.relativeRotationMultipliers = hairModParameters.relativeRotationMultipliers;
				}
				if ((hairModParameters.relativeRotationTargets as Dictionary) != undefined) {
					dynamicHairRope.relativeRotationTargets = hairModParameters.relativeRotationTargets;
				}
				if ((hairModParameters.minRotations as Dictionary) != undefined) {
					dynamicHairRope.minRotations = hairModParameters.minRotations;
				}
				if ((hairModParameters.maxRotations as Dictionary) != undefined) {
					dynamicHairRope.maxRotations = hairModParameters.maxRotations;
				}
				
				// Populate the elasticity parameters
				if ((hairModParameters.segmentElasticities as Dictionary) != undefined) {
					dynamicHairRope.segmentElasticities = hairModParameters.segmentElasticities;
				}
				
				if ((hairModParameters.visualParent as String) != null) {
					// We need to replace the UpdateRopeGraphic method entirely.
					// The replacement method will perform the necessary conversion of physics-based Link positions (relative to g.sceneLayer)
					// into a custom (x,y) coordinate space -- belonging to whichever element has been designated as "visualParent" for this Rope.
					
					wrappedMethod = methodWrapper(updateRopeGraphic_CustomParent, dynamicHairRope);
					var updateRopeGraphic = (lProxy as Class).createProxy(dynamicHairRope, "updateRopeGraphic");
					updateRopeGraphic.addPre(wrappedMethod, true);
					updateRopeGraphic.hooked = false;
				}

				// Establish an anchor.  By default, it's the canonical position of the zeroth segment -- but custom anchors are also allowed.
				if ((hairModParameters.anchorSource as String) != null) {
					dynamicHairRope.anchorSource = findObjectByPath(g, hairModParameters.anchorSource);
					
					if ((hairModParameters.hideAnchor as Boolean) == true) {
						(dynamicHairRope.anchorSource as DisplayObject).visible = false;
					}
				}
				dynamicHairRope.anchorPoint = new Point(dynamicHairRope.segments[0].x, dynamicHairRope.segments[0].y);
				
				// Bodyparts in SDT are eligible for skin-tone switching (light, pale, tan, dark).  This is done by
				// defining four Keyframes within the object; SDT switches between them when appropriate.
				// Unfortunately, Dynamic Hair segments are loaded as MovieClip objects, and a MovieClip will immediately
				// begin to Play() when it hits the stage.  Thus, it will rapidly strobe through the available skin tones.
				// 
				// If the modder has indicated that a segment (or an entire Rope!) is a bodypart with skin-tone Keyframes,
				// then we will do two things:
				// 1 - suppress the AutoPlay behaviour to prevent strobing
				// 2 - whenever the sking tone is changed in SDT, mirror that change onto the relevant Segment(s)
				if ((hairModParameters.useSkinPalette as Dictionary) != undefined) {
					var useSkinPalette:Boolean;
					var setSkin = (lProxy as Class).createProxy(g.characterControl, "setSkin");
					
					for (var segmentNum:* in (hairModParameters.useSkinPalette as Dictionary)) {
						try {
							useSkinPalette = ((hairModParameters.useSkinPalette as Dictionary)[segmentNum] as Boolean);
							var currentSegment:MovieClip = (dynamicHairRope.segments[segmentNum] as MovieClip);
							if (useSkinPalette) {
								// Register the PRE method so that this segment will respond to Skin-Colour changes
								// which are made by SDT (presumably due to user action within the UI).
								wrappedMethod = setSkin_RopeSegment_Wrapper(currentSegment);
								setSkin.addPre(wrappedMethod, true);
								
								// Perform an immediate "reaction" to ensure that the correct skin-colour is displayed
								// when the Rope is loaded onto the stage.
								setSkin_RopeSegment(currentSegment, g.characterControl.currentSkin);
							}
						} catch (myError:Error) {}
					}
				}
				
				if ((hairModParameters.monitorTension as Boolean) == true) {
					dynamicHairRope.monitorTension = true;
					dynamicHairRope.properLength = calculateRopeLength(dynamicHairRope, false);
				}

				dynamicHairRope.maximumY = Number.MAX_VALUE;
				if ((hairModParameters.floorAtKneeLevel as Boolean) == true) {
					// Apply a custom offset (if one has been specified)
					if ((hairModParameters.floorKneeOffset as Point) != null) { dynamicHairRope.floorKneeOffset = hairModParameters.floorKneeOffset; }
					dynamicHairRope.floorKneeOffset = dynamicHairRope.floorKneeOffset || new Point(85,85);
					
					// Attach to the IK update method so that the Rope will notice any Knee movement
					var newTarget = (lProxy as Class).createProxy(g.her.torsoIK, "newTarget");
					newTarget.addPre(newTarget_IK_Wrapper(dynamicHairRope), true);
					
					// Perform an immediate "reaction" to ensure that the Rope knows the current Knee position
					newTarget_IK(dynamicHairRope, g.her.torsoIK.targetPoint, g.her.torsoIK.targetPointCoordinateSpace, false);
				}

				if ((hairModParameters.rgbElement as String) != null) {
					// Ensure that the element is valid
					var elementHelper = (g.characterControl[hairModParameters.rgbElement] as CharacterElementHelper);
					if (elementHelper != null) {
						// Proxy the SetFill function so that we can react to any ARGB slider activity in the UI
						var setFill = (lProxy as Class).createProxy(elementHelper, "setFill");
						setFill.addPre(setFill_Rope_Wrapper(dynamicHairRope, elementHelper), false);
						
						// Perform an immediate "reaction" to ensure that the Rope has the correct colour-fill
						setFill_Rope(dynamicHairRope, elementHelper, elementHelper.rgb1, "rgbFill");
						setFill_Rope(dynamicHairRope, elementHelper, elementHelper.rgb2, "rgbFill2");
					}
				}
								
				var hairMod = new LoadedMod(g.customElementLoader.loadingModPackage,hairModParameters,dynamicHairRope);
				g.customElementLoader.instancedModElements.push(hairMod);
				g.customElementLoader.loadingModPackage.addElement(hairMod);
			} catch (myError:Error) {
				var ropeName = "unknown";
				if (dynamicHairRope != undefined && dynamicHairRope.ropeGraphic != null) { ropeName = dynamicHairRope.ropeGraphic.name; }
				main.updateStatusCol("Dynamic Hair Strand Initialization Error: " + ropeName + " " + myError.toString(),"#FF0000");
			}
			
			// Finally, we must return a non-null value.  The Loader's lProxy mechanism will detect this,
			// and it will refrain from invoking the proxied method (i.e. the vanilla hair-loading code).
			return true;
		}

		// Functor wrapper.  Use with ADDPRE and ADDPOST calls, based on ModGuy's suggestion.
		// Replaces a previous (very sloppy) implementation which relied on a hardcoded set of pseudo-parameters.
		public static function methodWrapper(method:Function, parameter:Object):Function {
			return function():void{
				method(parameter);
			}
		}
		
		public static function methodWrapper2(method:Function, parameter1:Object, parameter2:Object):Function {
			return function():void{
				method(parameter1, parameter2);
			}
		}
		
		function physicsStep(rope:Object):void {
			// Step 1: Move links back to their canonical positions
			moveLinksToAnchors(rope, true);

			// Step 2: Apply the gravity vector to each ropelink
			applyGravity(rope);

			// Step 3: Proximal-to-distal correction of segment lengths and orientation
			adjustSegments(rope);
			
			// Step 4: Distal-to-proximal rotation propagation
// TODO: this feature has been temporarily shelved due to runtime instability, and the lack of a solid use-case upon which to refine it.
		}

		function moveLinksToAnchors(rope:Object, recursive:Boolean) {
			// Move this rope's zeroth link to its anchor position
			if ((rope.anchored as Boolean) == true) {
				if (rope.anchorSource as DisplayObject) { rope.anchorPoint = new Point(rope.anchorSource.x, rope.anchorSource.y); }
				rope.currentAnchor = g.sceneLayer.globalToLocal((rope.anchorContainer as DisplayObjectContainer).localToGlobal(rope.anchorPoint));
				rope.links[0].x = rope.currentAnchor.x;
				rope.links[0].y = rope.currentAnchor.y;
			}
			
			// Apply the same correction to any subsidiary ropes
			if (!recursive) { return; }
			for (var ropeName:* in (rope.sharedRopes as Dictionary)) {
				if (((rope.sharedRopes[ropeName] as Rope).doNotSimulate as Boolean) == true) {
					moveLinksToAnchors(rope.sharedRopes[ropeName], false);
				}
			}
		}
		
		function applyGravity(rope:Object) {
			var gravityRadians:Number = (180 + rope.gOffset) * (Math.PI / 180);
			rope.gravityDirection.x = Math.sin(gravityRadians);
			rope.gravityDirection.y = -Math.cos(gravityRadians);
			// Note that the iteration begins at index 0.  The zeroth link is USUALLY anchored and immune to gravity, but we'll check just in case.
			for(var linkIndex:uint = 0; linkIndex < rope.ropeLength + 1; linkIndex ++) {
				rope.massAndInfluence = 1.0;
				if((rope.sharedLinkInfluences as Dictionary) != null) { 
					rope.massAndInfluence = ((rope.sharedLinkInfluences[linkIndex] as Number) || rope.massAndInfluence);
					rope.massAndInfluence = Math.max(INFLUENCE_MINIMUM, Math.min(INFLUENCE_MAXIMUM, rope.massAndInfluence));
				};
				rope.massAndInfluence *= rope.links[linkIndex].mass;
				rope.links[linkIndex].moveInfluenced(rope.gravityDirection, rope.massAndInfluence, rope.maximumY);
			}
		}
		
		function detachFrameEventListener(rope:Object) {
			try {
				rope.removeEventListener(Event.ENTER_FRAME, rope.enterFrame);
			} catch (myError:Error) {}
		}

		function adjustSegments(rope:Object) {
			try {
				var currentSegment:DisplayObject = (rope.segments[0] as DisplayObject);
				// During recursion, we need to track the previous Segment so that we can use it as
				// a reference for determining "effective" rotation of the current Segment
				var previousSegment:DisplayObject = rope.anchorContainer;
				// For the Zeroth segment (first recursive step), we must use an anatomy object 
				// such as g.her (the head object) as our orientation reference.
				
				// Begin recursing through the Segments.  We won't make any permanent alterations to the segments,
				// but for each one we'll assess its orientation (aka its "effective" rotation) and shift its
				// endpoint (if necessary).
				
				adjustSegment(rope, 0, 1, currentSegment, previousSegment);
				
				// All segments have been rotated.  Do we need to check Tension?
				if ((rope.monitorTension as Boolean) == true) {
					rope.tension = calculateRopeLength(rope, true) / (rope.properLength as Number);
				}
			} catch (myError:Error) {
				main.updateStatusCol("Dynamic Hair Anim Err: " + rope.ropeGraphic.name + " " + myError.toString(),"#FF0000");
			}
		}

		function adjustSegment(rope:Object, i:uint, step:int, currentSegment:DisplayObject, previousSegment:DisplayObject) {
			// Lookup the relevant configuration parameters
			rope.currentLinkInfluence = 1.0; rope.nextLinkInfluence = 1.0; rope.proximalElasticityFactor = DEFAULT_ELASTICITY_PROXIMAL; rope.distalElasticityFactor = DEFAULT_ELASTICITY_DISTAL; rope.allowElongation = false; rope.allowCompression = false;
			if((rope.sharedLinkInfluences as Dictionary) != undefined) { 
				rope.currentLinkInfluence = (rope.sharedLinkInfluences[i] as Number) || rope.currentLinkInfluence;
				rope.nextLinkInfluence = (rope.sharedLinkInfluences[i + step] as Number) || rope.nextLinkInfluence;
			}
			rope.currentLinkInfluence = Math.max(INFLUENCE_MINIMUM, Math.min(INFLUENCE_MAXIMUM, rope.currentLinkInfluence));
			rope.nextLinkInfluence = Math.max(INFLUENCE_MINIMUM, Math.min(INFLUENCE_MAXIMUM, rope.nextLinkInfluence));
			if((rope.proximalElasticityFactors as Dictionary) != undefined) {
				rope.proximalElasticityFactor = (rope.proximalElasticityFactors[currentSegment.name] as Number) || (rope.proximalElasticityFactors[i] as Number) || rope.proximalElasticityFactor;
			}
			rope.proximalElasticityFactor = Math.max(ELASTICITY_MINIMUM, Math.min(ELASTICITY_MAXIMUM, rope.proximalElasticityFactor));
			if((rope.distalElasticityFactors as Dictionary) != undefined) {
				rope.distalElasticityFactor = (rope.distalElasticityFactors[currentSegment.name] as Number) || (rope.distalElasticityFactors[i] as Number) || rope.distalElasticityFactor;
			}
			rope.distalElasticityFactor = Math.max(ELASTICITY_MINIMUM, Math.min(ELASTICITY_MAXIMUM, rope.distalElasticityFactor));
			if((rope.allowElongations as Dictionary) != undefined) {
				rope.allowElongation = (rope.allowElongations[currentSegment.name] as Boolean) || (rope.allowElongations[i] as Boolean) || rope.allowElongation;
			}
			if((rope.allowCompressions as Dictionary) != undefined) {
				rope.allowCompression = (rope.allowCompressions[currentSegment.name] as Boolean) || (rope.allowCompressions[i] as Boolean) || rope.allowCompression;
			}
			
			rope.relativeRotationTarget = 0.0; rope.relativeRotationMultiplier = 1.0; rope.minRelativeRotation = -720.0; rope.maxRelativeRotation = 720.0;
			if ((rope.relativeRotationTargets as Dictionary) != undefined) {
				rope.relativeRotationTarget = (rope.relativeRotationTargets[currentSegment.name] as Number) || (rope.relativeRotationTargets[i] as Number) || rope.relativeRotationTarget;
			}
			if ((rope.relativeRotationMultipliers as Dictionary) != undefined) {
				rope.relativeRotationMultiplier = (rope.relativeRotationMultipliers[currentSegment.name] as Number) || (rope.relativeRotationMultipliers[i] as Number) || rope.relativeRotationMultiplier;
			}
			if ((rope.minRotations as Dictionary) != undefined) {
				rope.minRelativeRotation = (rope.minRotations[currentSegment.name] as Number) || (rope.minRotations[i] as Number) || rope.minRelativeRotation;
			}
			if ((rope.maxRotations as Dictionary) != undefined) {
				rope.maxRelativeRotation = (rope.maxRotations[currentSegment.name] as Number) || (rope.maxRotations[i] as Number) || rope.maxRelativeRotation;
			}
			(currentSegment as Object).oldRotation = Number.NEGATIVE_INFINITY;
			
			// If the parameters include a non-trivial Rotation effect, then perform it
			if ((rope.relativeRotationMultiplier != 1.0) || (rope.minRelativeRotation > -720.0) || (rope.maxRelativeRotation < 720.0)) {
				// Establish a geometrical context for this Segment
				rope.currentSegmentRotation = currentSegment.rotation;
				rope.previousSegmentRotation = previousSegment.rotation;
				rope.relativeRotation = (rope.currentSegmentRotation - (rope.previousSegmentRotation + rope.relativeRotationTarget) + 540.0) % 360.0 - 180.0;

				// Calculate the current orientation info (based on gravity and motion)
				rope.currentVector = rope.currentVector || new Point();
				rope.currentVector.x = rope.links[i + step].x - rope.links[i].x;
				rope.currentVector.y = rope.links[i + step].y - rope.links[i].y;
				rope.vectorOrigin = (rope.ropeGraphic as DisplayObjectContainer).globalToLocal( (g.sceneLayer as DisplayObjectContainer).localToGlobal(rope.links[i] as Point));
				rope.vectorEndpoint = (rope.ropeGraphic as DisplayObjectContainer).globalToLocal( (g.sceneLayer as DisplayObjectContainer).localToGlobal(rope.links[i+1] as Point));
				rope.currentVector.x = rope.vectorEndpoint.x - rope.vectorOrigin.x;
				rope.currentVector.y = rope.vectorEndpoint.y - rope.vectorOrigin.y;
				// Calculate the segment orientation info (based ONLY on segment rotation differences)
				rope.segmentVector = flash.geom.Point.polar(currentSegment.scaleY * rope.segLength[i], (currentSegment.rotation + 90) * Math.PI / 180.0);
				// Blend these two numbers according to the configuration parameter.
				// This establishes a CONTEXT against which we'll perform our Matrix transformation later on.
				rope.rotationVector = flash.geom.Point.interpolate(rope.segmentVector, rope.currentVector, rope.rotationBlending);
				(currentSegment as Object).oldRotation = g.getAngle(rope.rotationVector.x, rope.rotationVector.y) + 180;

				// Rotate the segment so that it is approaches the orientation of its predecessor (plus some offset).
				// The STRENGTH of this approach is set by the "relativeRotationMultiplier" parameter.
				// The OFFSET is specified (in degrees) by the "relativeRotationTarget" parameter.
				rope.currentSegmentRotation -= rope.relativeRotation * (1.0 - rope.relativeRotationMultiplier);

				// Apply rotation limits
				rope.relativeRotation = (rope.currentSegmentRotation - rope.previousSegmentRotation + 540.0) % 360.0 - 180.0;		// Refresh
				if (Math.max(Math.abs(rope.minRelativeRotation), Math.abs(rope.maxRelativeRotation)) == 720.0){
					// There are no constraints in-effect; do nothing
				} else if ( (rope.relativeRotation - rope.minRelativeRotation + 720.0) % 360.0 < (rope.relativeRotation - rope.maxRelativeRotation + 720.0) % 360.0) {
					// The number is within the valid range; do nothing
				} else {
					// The number is out of bounds; nudge it to the nearer of the two constraint values
					if (Math.abs((rope.minRelativeRotation - rope.relativeRotation + 180) % 360.0 - 180.0) < Math.abs((rope.maxRelativeRotation - rope.relativeRotation + 180.0) % 360.0 - 180.0)) {
						// Nearer to minRotation
						rope.currentSegmentRotation = rope.previousSegmentRotation + rope.minRelativeRotation;
					} else {
						// Nearer to maxRotation
						rope.currentSegmentRotation = rope.previousSegmentRotation + rope.maxRelativeRotation;
					}
				}

				// Apply the change
				currentSegment.rotation = (720.0 + rope.currentSegmentRotation) % 360.0;
				
				// Our strategy is: 
				// 1 - calculate the translational equivalent of the rotation that we performed
				// 2 - apply this translation to the next Link (the endpoint of the current Segment)
				// 3 - apply the same translation to remaining Links(i+1...n)
						// this is no longer true because it was found to be unstable.  Step 3 is now skipped.
						// TODO: Maybe have the "adjust next Link only" as default policy but with an "apply to all" param option?
				// 4 - LEAVE THE SEGMENTS ALONE!  They'll get updated by the SDT physics engine based on our Link tweaks.
				
				// Note: this means that our change won't take effect until the next frame.  That's usually okay
				// because the delay is imperceptible to the player.  It also means that we're "at the mercy" of
				// SDT's logic - it's continually blending its physics rules with our overrides.
				
				// This means that modders should aim for their interventions to reach a point of equilibrium
				// - wherein this mod intervenes slightly on each frame, and SDT nudges slightly back.  If we've
				// used reasonable parameters, then the nudging will be sub-pixel.  If we've made bad decisions
				// (or skipped testing) then the user may see oscillation/jiggle.

				rope.desiredRotation = rope.desiredRotation || new Matrix(); 
				rope.desiredRotation.identity();
				MatrixTransformer.rotateAroundInternalPoint(rope.desiredRotation, rope.links[i].x, rope.links[i].y, currentSegment.rotation - (currentSegment as Object).oldRotation);

				rope.rotationGoal = rope.desiredRotation.transformPoint(rope.links[i+step]);
				rope.correctiveVector = new Point(rope.rotationGoal.x - rope.links[i+step].x, rope.rotationGoal.y - rope.links[i+step].y);
				for each (var link in rope.links.slice(i+step, i+step*2)){
					(link as RopeLink).moveInfluenced(rope.correctiveVector, rope.nextLinkInfluence);
					// Note: because of shared-influence blending, the RopeLink may not have moved as far as we would like it to.
					
// TODO: retroactively adjust the apparent Rotation to coincide with the change which we were ABLE to make?
// TODO: need a better use-case in order to refine this one.  Chain logic would be an obvious application, as would skirt-grid logic.
				}
			}
			
			// ASSERT: The next RopeLink has been moved into the appropriate orientation.
			// Now, we'll move it (linearly) within this orientation, so as to enforce Elasticity rules

			if ((rope.currentLinkInfluence * rope.proximalElasticityFactor > 0.0) || (rope.nextLinkInfluence * rope.distalElasticityFactor > 0.0)) {
				// Determine the actual length for this Segment, and its relation to the prefered/canonical length
				rope.linkDistance = flash.geom.Point.distance(rope.links[i], rope.links[i + step]); // = Math.sqrt(Math.pow(vector.x, 2) + Math.pow(vector.y, 2));
				rope.correctiveVector = rope.correctiveVector || new Point();
				// ERRATA: I'd like to use rope.setTo(x,y) here, but it isn't supported by all Flash Player versions
				rope.correctiveVector.x = rope.links[i+step].x - rope.links[i].x
				rope.correctiveVector.y = rope.links[i+step].y - rope.links[i].y;
				rope.correctiveVector.normalize(rope.segLength[i] - rope.linkDistance);
				// If we moved the distal RopeLink according to adjustedVector, then the actual length would match the canonical length.
				// We won't actually do so in most cases.  We'll allow the two values to diverge temporarily, because it makes for more believable motion
				// and better propagation of impulses through the Rope.

				if ((rope.allowElongation as Boolean) && (rope.segLength[i] < rope.linkDistance)) {
					// The segment is stretching beyond its canonical length, but this is ALLOWED by its config.  Do nothing.
				} else if ((rope.allowCompression as Boolean) && (rope.segLength[i] > rope.linkDistance)) {
					// The segment is compressing to less than its canonical length, but this is ALLOWED by its config.  Do nothing.
				} else {
					// Attempt to move the current RopeLink according to material elasticity
					rope.links[i].moveInfluenced(rope.correctiveVector, -1.0 * rope.currentLinkInfluence * rope.proximalElasticityFactor);
					// Attempt to move the next RopeLink according to material elasticity
					rope.links[i + step].moveInfluenced(rope.correctiveVector, 1.0 * rope.nextLinkInfluence * rope.distalElasticityFactor);
				}
			}
			
			// Recursive call
			if ((i + step) >= rope.segments.length) { }
			else if ((i + step) <= 0) { }
			else { adjustSegment(rope, i+step, step, rope.segments[i+step], currentSegment); }

			// Undo the rotation change that we originally made to this Segment
			if ((currentSegment as Object).oldRotation > Number.NEGATIVE_INFINITY) { currentSegment.rotation = (currentSegment as Object).oldRotation % 360.0; }
			// Note: it's important that we make this correction at the LAST possible moment.
			// We want the entire recursive operation to be complete while our Segment is in the altered positiong,
			// so that all of the later Segments in the chain can choose an orientation which makes sense w/r/t
			// the ALTERED orientation of THIS Segment.
			
			// We reset the Segment orientation only AFTER all of the necessary tinkering and interventions have
			// been performed -- when we're about to "hand the reins" back to SDT.
		}

		// Helper function.  Attempts to traverse a dot-delimited path (e.g. "g.her.rightArm") and return the ultimate object
		function findObjectByPath(currentObject:Object, dottedPath:String):DisplayObject {
			// Check for end of recursion
			if (dottedPath.length == 0) { return (currentObject as DisplayObject); }

			// Recursive case: proceed one step further along the path
			var firstDotIndex:int = dottedPath.indexOf(".");
			// Special case: if there are no dots left in the path, consume the entire string in the next pass
			if (firstDotIndex == -1) { firstDotIndex = dottedPath.length; }

			// Proceed with the next step: lookup a child object of the current object, then apply the remaining
			// dotted-path to it via a recursive call
			var firstObjectName:String = dottedPath.substr(0, firstDotIndex);
			var remainingPath:String = dottedPath.substr(firstDotIndex + 1);
			var nextObject:Object = currentObject[firstObjectName];
			if (nextObject == null) { nextObject = (currentObject as DisplayObjectContainer).getChildByName(firstObjectName); }
			if (nextObject == null) { return null; }
			return findObjectByPath(nextObject, remainingPath);
		}
		
		public static function findDescendantsByName(targetElement:DisplayObjectContainer, targetName:String):Array {
			// Base case
			if (targetElement.name == targetName) { return [targetElement]; }

			// Recursive case
			var returnElements:Array = new Array();
			for (var i:uint = 0; i<targetElement.numChildren; i++) {
				if (!(targetElement.getChildAt(i) as DisplayObjectContainer)) {
					// Child element is not eligible; skip it.
					continue;
				}
				returnElements = returnElements.concat(findDescendantsByName((targetElement.getChildAt(i) as DisplayObjectContainer), targetName));
			}
			return returnElements;
		}

		function updateRopeGraphic_CustomParent(rope:Object) {
			if (rope.segments.length == 0) { return; }

			var segmentVector:Point = null;
			var segmentLength:Number = NaN;
			var angle:Number = NaN;
			var segmentOrigin:Point;
			var segmentEndpoint:Point;
			
			for(var i:uint = 0; i < rope.ropeLength; i++) {
				segmentOrigin = (rope.ropeGraphic as DisplayObjectContainer).globalToLocal( (g.sceneLayer as DisplayObjectContainer).localToGlobal(rope.links[i] as Point));
				segmentEndpoint = (rope.ropeGraphic as DisplayObjectContainer).globalToLocal( (g.sceneLayer as DisplayObjectContainer).localToGlobal(rope.links[i+1] as Point));				
				
				segmentLength = flash.geom.Point.distance(segmentOrigin, segmentEndpoint);
				segmentVector = (segmentEndpoint).subtract(segmentOrigin);
				angle = g.getAngle(segmentVector.x, segmentVector.y) + 180;
				
				rope.segments[i].x = segmentOrigin.x;
				rope.segments[i].y = segmentOrigin.y;
				rope.segments[i].rotation = angle;
				rope.segments[i].scaleY = segmentLength / rope.segLength[i];
			}
		}
				
		function setSkin_RopeSegment_Wrapper(segment:MovieClip) {
			return function(skinIndex:uint, clearTan:Boolean = true):void {
				setSkin_RopeSegment(segment, skinIndex, clearTan);
			}
		}

		function setSkin_RopeSegment(segment:MovieClip, skinIndex:uint, clearTan:Boolean = false) {
			try {
				var skinType:String = g.dataName(g.characterControl.skinNameList[skinIndex]);
				segment.gotoAndStop(skinType);
			} catch (myError:Error) {}
		}

		function newTarget_IK_Wrapper(rope:Object){
			return function(target:Point, parentObject:DisplayObject, jump:Boolean = false):void {
				newTarget_IK(rope, target, parentObject, jump);
			}
		}

		function newTarget_IK(rope:Object, target:Point, parentObject:DisplayObject, jump:Boolean) {
			try {
				// Apply the custom offset
				target = target.add(rope.floorKneeOffset);
				// Shift to global coordinate space
				var globalTarget:Point = parentObject.localToGlobal(target);
				rope.maximumY = (g.sceneLayer as DisplayObject).globalToLocal(globalTarget).y;
			} catch (myError:Error) {}
		}

		function setFill_Rope_Wrapper(rope:Object, elementHelper:Object) {
			return function(argb:Object, targetName:String = "rgbFill"):void {
				setFill_Rope(rope, elementHelper, argb, targetName);
			}
		}
		
		function setFill_Rope(rope:Object, elementHelper:Object, argb:Object, targetName:String = "rgbFill") : void {
			try { 
				var argbTransform:ColorTransform = new ColorTransform(1,1,1,argb.a,argb.r,argb.g,argb.b);
				if (rope.ropeGraphic.fillOverrides as Dictionary) { targetName = (rope.ropeGraphic.fillOverrides as Dictionary)[targetName] || targetName; }
				elementHelper.tryToSetFillChildren(rope.ropeGraphic,targetName,argbTransform);
			} catch (myError:Error) { }
		}

		function calculateRopeLength(rope:Object, includeStretch:Boolean = true):Number {
			var lengthSum:Number = 0.0;
			for (var segIndex:int = 0; segIndex < (rope.segments as Array).length - 1; segIndex++){
				if (includeStretch) {
					lengthSum += (rope.segments[segIndex] as MovieClip).scaleY * rope.segLength[segIndex];
				} else {
					lengthSum += rope.segLength[segIndex];
				}
			}
			return lengthSum;
		}
		
		function convertSegmentNamesToLinkIndices(dict:Dictionary, rope:Object):Dictionary {
			// Clone the dictionary
			var convertedDictionary:Dictionary = new Dictionary();
			for (var key:* in (dict as Dictionary)) {
				convertedDictionary[key] = dict[key];
			}
			
			// Replace any segmentName keys and replace them with equivalent linkIndex keys
			for (var segmentName:* in (dict as Dictionary)) {
				if ((segmentName as String) == null) { continue; } 		// Ignore numeric keys
				try {
					// Get the index of the segment
					var linkIndex:int = (rope.segments as Array).indexOf(((rope.ropeGraphic as MovieClip).getChildByName(segmentName as String)));
					if (linkIndex == -1) { continue; }
					// Add 1 (heuristic: Segment-name configuration always applies to the Distal link of each Segment)
					linkIndex ++;
					// Add the LinkIndex reference
					convertedDictionary[linkIndex] = convertedDictionary[segmentName];
				} catch (myError:Error) { 
				} finally {
					// Remove the SegmentName reference
					delete convertedDictionary[segmentName];
				}
			}
			return convertedDictionary;
		}
		
		function doUnload() {
			try {
				var constructorProxy = (lProxy as Class).checkProxied(g.customElementLoader, "addDynamicHairMod");
				if (constructorProxy) { constructorProxy.removePre(addDynamicHairMod_Pre); }
				main[modName] = null;
			} catch (myError:Error) { }
		}
		
		public static function countKeys(myDictionary:flash.utils.Dictionary):int {
			var n:int = 0;
			for (var key:* in myDictionary) {
				n++;
			}
			return n;
		}
	}
}