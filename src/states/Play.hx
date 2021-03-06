package states;

import components.FeatherRockAnimator;
import components.FeatherRockPhysics;
import components.GroundDetector;
import components.MouseBulletTime;
import luxe.Particles;
import luxe.Visual;
import motion.Actuate;
import phoenix.Camera;
import luxe.Color;
import luxe.components.sprite.SpriteAnimation;
import luxe.Entity;
import luxe.importers.tiled.TiledMap;
import luxe.importers.tiled.TiledObjectGroup;
import luxe.Input;
import luxe.Log;
import luxe.physics.nape.DebugDraw;
import luxe.Scene;
import luxe.Sprite;
import luxe.Vector;
import nape.geom.Vec2;
import nape.phys.Body;
import nape.phys.BodyType;
import nape.shape.Circle;
import nape.shape.Polygon;
import phoenix.Batcher;
import phoenix.Texture;
import luxe.Parcel;
import luxe.Rectangle;
import luxe.States;
import luxe.Text;

enum CollectibleType {
	magic;
	goblins;
	gold;
}

class Play extends State {
	var tilemap:TiledMap;
	var featherRock:Sprite;
	var terrain:Array<Body> = new Array<Body>();
	var hudBatcher:Batcher;
	var bgBatcher:Batcher;

	var playScene:Scene;

	var spawnPoint:Vector = new Vector();

	var featherRockIsBurning:Bool = false;

	public function new() {
		super({ name: 'Play' });
		playScene = new Scene('play');
	}

	var checkpointMagic:Float = 0;

	override function onenter<T>(_:T) {
		Luxe.camera.zoom = 3;
		//Luxe.renderer.clear_color = new Color().rgb(0x719ecf);
		Luxe.renderer.clear_color = new Color().rgb(0x0b1827);

		Main.musicManager.loop("theme");

		var level:String = "assets/maps/level" + Main.gameData.currentLevel + ".tmx";
		trace("Loading level: " + level);

		createBG();

		tilemap = new TiledMap({
			tiled_file_data: Luxe.resources.find_text(level).text,
			asset_path: "assets/maps/"
		});

		tilemap.display({ filter: FilterType.nearest });

		Luxe.camera.pos.set_xy(0, 0);

		checkpointMagic = TweakConfig.startMagic;

		// load all the objects
		for(group in tilemap.tiledmap_data.object_groups) {
			switch(group.name) {
				case "Collisions": {
					for(object in group.objects) {
						switch(object.object_type) {
							case TiledObjectType.rectangle: {
								var box = new Body(BodyType.STATIC);
								box.shapes.add(new Polygon(Polygon.box(object.width, object.height)));
								box.position.setxy(object.pos.x + object.width / 2, object.pos.y + object.height / 2);
								box.space = Luxe.physics.nape.space;
								box.cbTypes.add(PhysicsTypes.ground);
								terrain.push(box);

								if(Main.drawer != null) Main.drawer.add(box);
							}

							default: {}
						}
					}
				}

				case "FeatherRock": {
					for(object in group.objects) {
						spawnPoint.set_xy(object.pos.x, object.pos.y);
						spawnFeatherRock(spawnPoint);
					}
				}

				case "Breakable": {
					for(object in group.objects) {
						spawnBreakableBlock(object.pos);
					}
				}

				case "Chests": {
					for(object in group.objects) {
						spawnChest(object.pos, object.properties.get('amount') == null ? TweakConfig.defaultChestGold : Std.parseFloat(object.properties.get('amount')));
					}
				}

				case "Elves": {
					for(object in group.objects) {
						spawnElf(object.pos);
					}
				}

				case "Goblins": {
					for(object in group.objects) {
						spawnGoblin(object.pos);
					}
				}

				case "Goal": {
					for(object in group.objects) {
						spawnExit(new Rectangle(object.pos.x, object.pos.y, object.width, object.height));
					}
				}

				case "Fire": {
					for(object in group.objects) {
						spawnFire(object.pos, object.properties.get('direction') == null ? 90 : Std.parseFloat(object.properties.get('direction')));
					}
				}

				case "Checkpoints": {
					for(object in group.objects) {
						spawnCheckpoint(new Rectangle(object.pos.x, object.pos.y, object.width, object.height));
					}
				}

				default: {}
			}
		}

		createUI();
	}

	override function onleave<T>(_:T) {
		for(body in terrain) {
			if(Main.drawer != null) Main.drawer.remove(body);
			Luxe.physics.nape.space.bodies.remove(body);
		}
		terrain.splice(0, terrain.length);
		playScene.empty();
		tilemap.visual.destroy();
		trace("Left play");
	}

	function createBG() {
		bgBatcher = new Batcher(Luxe.renderer, "bg batcher");
		var bgView:Camera = new Camera();
		bgBatcher.view = bgView;
		bgBatcher.layer = -1;
		Luxe.renderer.add_batch(bgBatcher);

		var bgTexture:Texture = Luxe.resources.find_texture("assets/cinematic/mountain bg.png");
		bgTexture.filter = FilterType.nearest;
		var bg:Sprite = new Sprite({
			texture: bgTexture,
			name: 'bg',
			name_unique: true,
			pos: Luxe.screen.mid.clone(),
			size: new Vector(1024, 1024),
			batcher: bgBatcher,
			scene: playScene
		});
	}

	function createUI() {
		hudBatcher = new Batcher(Luxe.renderer, 'hud batcher');
		var hudView:Camera = new Camera();

		hudBatcher.view = hudView;
		hudBatcher.layer = 2;
		Luxe.renderer.add_batch(hudBatcher);

		/*var magicText = new luxe.Text({
			text: "Magic",
			pos: new Vector(4, 4),
			point_size: 16,
			font: Main.uiFont,
			batcher: hudBatcher,
			scene: playScene
		});
		magicText.add(new components.MagicDisplay(magicText));*/

		var uiTexture:Texture = Luxe.resources.find_texture("assets/sprites/indicator ui.png");
		uiTexture.filter = FilterType.nearest;
		var ui:Visual = new Visual({
			pos: new Vector(0, 0),
			size: new Vector(256, 256),
			texture: uiTexture,
			batcher: hudBatcher,
			scene: playScene
		});

		var magicBarTexture:Texture = Luxe.resources.find_texture("assets/sprites/magicbar.png");
		magicBarTexture.filter = FilterType.nearest;
		var magicBar:Sprite = new Sprite({
			pos: new Vector(58, 10),
			size: new Vector(100, 8),
			texture: magicBarTexture,
			batcher: hudBatcher,
			scene: playScene,
			depth: 1,
			centered: false
		});
		magicBar.add(new components.PlayerDataBarDisplay(CollectibleType.magic, magicBar));

		var magicText = new luxe.Text({
			text: "Magic",
			pos: new Vector(180, 8),
			point_size: 16,
			font: Main.uiFont,
			batcher: hudBatcher,
			scene: playScene
		});
		magicText.add(new components.PlayerDataTextDisplay(CollectibleType.magic, magicText));

		var goblinsBarTexture:Texture = Luxe.resources.find_texture("assets/sprites/goblinsbar.png");
		goblinsBarTexture.filter = FilterType.nearest;
		var goblinsBar:Sprite = new Sprite({
			pos: new Vector(58, 24),
			size: new Vector(100, 8),
			texture: goblinsBarTexture,
			batcher: hudBatcher,
			scene: playScene,
			depth: 1,
			centered: false
		});
		goblinsBar.add(new components.PlayerDataBarDisplay(CollectibleType.goblins, goblinsBar));

		var goblinsText = new luxe.Text({
			text: "Goblins",
			pos: new Vector(180, 22),
			point_size: 16,
			font: Main.uiFont,
			batcher: hudBatcher,
			scene: playScene
		});
		goblinsText.add(new components.PlayerDataTextDisplay(CollectibleType.goblins, goblinsText));

		var goldBarTexture:Texture = Luxe.resources.find_texture("assets/sprites/goldbar.png");
		goldBarTexture.filter = FilterType.nearest;
		var goldBar:Sprite = new Sprite({
			pos: new Vector(58, 38),
			size: new Vector(100, 8),
			texture: goldBarTexture,
			batcher: hudBatcher,
			scene: playScene,
			depth: 1,
			centered: false
		});
		goldBar.add(new components.PlayerDataBarDisplay(CollectibleType.gold, goldBar));

		var goldText = new luxe.Text({
			text: "gold",
			pos: new Vector(180, 36),
			point_size: 16,
			font: Main.uiFont,
			batcher: hudBatcher,
			scene: playScene
		});
		goldText.add(new components.PlayerDataTextDisplay(CollectibleType.gold, goldText));

		var featherRockTexture:Texture = Luxe.resources.find_texture("assets/sprites/featherrock.png");
		featherRockTexture.filter = FilterType.nearest;
		var rock:Sprite = new Sprite({
			name: 'disp',
			name_unique: true,
			pos: new Vector(29, 27),
			size: new Vector(32, 32),
			texture: featherRockTexture,
			batcher: hudBatcher,
			scene: playScene,
			depth: 2
		});
		var anim:SpriteAnimation = rock.add(new SpriteAnimation({ name: 'SpriteAnimation' }));
		anim.add_from_json_object(Luxe.resources.find_json('assets/sprites/featherrock.json').json);
		anim.animation = 'flying idle';
		anim.play();
	}

	function spawnFeatherRock(pos:Vector) {
		Main.playerData.magic = checkpointMagic;
		var featherRockTexture:Texture = Luxe.resources.find_texture("assets/sprites/featherrock.png");
		featherRockTexture.filter = FilterType.nearest;
		var rock:Sprite = new Sprite({
			name: 'FeatherRock',
			pos: pos,
			size: new Vector(16, 16),
			texture: featherRockTexture,
			scene: playScene
		});

		rock.add(new FeatherRockPhysics());
		rock.add(new components.FeatherRockControls());

		var anim:SpriteAnimation = rock.add(new SpriteAnimation({ name: 'SpriteAnimation' }));
		anim.add_from_json_object(Luxe.resources.find_json('assets/sprites/featherrock.json').json);
		anim.animation = 'flying idle';
		anim.play();

		rock.add(new GroundDetector());
		rock.add(new FeatherRockAnimator());
		rock.add(new MouseBulletTime());
		rock.add(new components.LazyCameraFollow());
		rock.add(new components.ShakeCameraOnHit());
		rock.add(new components.FeatherRockDiver());
		rock.add(new components.FeatherRockDiveDrawer());
		rock.add(new components.LoseMagicOverTime(TweakConfig.magicDrainSpeed, burnFeathers));

		//rock.add(new components.PlaySoundOnHit("groundhit", [PhysicsTypes.ground]));
		//rock.add(new components.PlaySoundOnHit("bodywhack", [PhysicsTypes.actor]));

		featherRock = rock;
	}

	function spawnBreakableBlock(pos:Vector) {
		var blockTexture:Texture = Luxe.resources.find_texture("assets/sprites/breakable_block.png");
		blockTexture.filter = FilterType.nearest;

		var block = new Sprite({
			name: 'BreakableBlock',
			name_unique: true,
			pos: pos,
			size: new Vector(16, 16),
			texture: blockTexture,
			scene: playScene
		});
		block.add(new components.Destructible(featherRock));
		block.add(new components.OneShotParticlesOnDestroy(new Color().rgb(0x8a5828)));
		block.add(new components.PlaySoundOnDestroyed("blockbreak"));
	}

	function spawnChest(pos:Vector, amount:Float) {
		var chestTexture:Texture = Luxe.resources.find_texture("assets/sprites/chest.png");
		chestTexture.filter = FilterType.nearest;

		var block = new Sprite({
			name: 'Chest',
			name_unique: true,
			pos: pos.clone().add_xyz(16, 8),
			size: new Vector(32, 16),
			texture: chestTexture,
			scene: playScene
		});
		block.add(new components.Destructible(featherRock));
		block.add(new components.OneShotParticlesOnDestroy(new Color().rgb(0x8a5828)));
		block.add(new components.PlaySoundOnDestroyed("blockbreak"));
		block.add(new components.GiveOnDestroy(CollectibleType.gold, amount, featherRock));
	}

	function spawnElf(pos:Vector) {
		var elfTexture:Texture = Luxe.resources.find_texture("assets/sprites/elf.png");
		elfTexture.filter = FilterType.nearest;

		var elf = new Sprite({
			name: 'Elf',
			name_unique: true,
			pos: pos.add_xyz(8, 16),
			size: new Vector(16, 32),
			texture: elfTexture,
			scene: playScene
		});

		var anim:SpriteAnimation = elf.add(new SpriteAnimation({ name: 'SpriteAnimation' }));
		anim.add_from_json_object(Luxe.resources.find_json('assets/sprites/elf.json').json);
		anim.animation = 'walk';
		anim.play();

		elf.add(new components.Destructible(featherRock, BodyType.DYNAMIC));
		elf.add(new components.OneShotParticlesOnDestroy(new Color().rgb(0xcf0000)));
		elf.add(new components.WalkBackAndForth(TweakConfig.elfWalkSpeed));
		elf.add(new components.GiveOnDestroy(CollectibleType.magic, TweakConfig.elfMagic, featherRock));
		//elf.add(new components.PlaySoundOnDestroyed("soul"));
	}

	function spawnGoblin(pos:Vector) {
		var goblinTexture:Texture = Luxe.resources.find_texture("assets/sprites/goblin.png");
		goblinTexture.filter = FilterType.nearest;

		var goblin = new Sprite({
			name: 'goblin',
			name_unique: true,
			pos: pos.add_xyz(8, 16),
			size: new Vector(16, 18),
			texture: goblinTexture,
			scene: playScene
		});

		var anim:SpriteAnimation = goblin.add(new SpriteAnimation({ name: 'SpriteAnimation' }));
		anim.add_from_json_object(Luxe.resources.find_json('assets/sprites/goblin.json').json);
		anim.animation = 'walk';
		anim.play();

		goblin.add(new components.Destructible(featherRock, BodyType.DYNAMIC));
		goblin.add(new components.OneShotParticlesOnDestroy(new Color().rgb(0xcf0000)));
		goblin.add(new components.WalkBackAndForth(TweakConfig.goblinWalkSpeed));
		goblin.add(new components.GiveOnDestroy(CollectibleType.goblins, 1, featherRock));
	}

	function spawnExit(rect:luxe.Rectangle) {
		var exit = new Entity({
			name: 'Exit',
			name_unique: true,
			scene: playScene
		});
		exit.add(new components.Trigger(rect, function() {
			Main.musicManager.play("tada");
			Main.gameData.currentLevel++;
			if(Main.gameData.currentLevel > TweakConfig.maxLevel) {
				Main.transition('End');
			}
			else {
				Main.transition('Play');
			}
		}));
	}

	function spawnCheckpoint(rect:luxe.Rectangle) {
		var checkpoint = new Entity({
			name: 'Checkpoint',
			name_unique: true,
			scene: playScene
		});
		checkpoint.add(new components.Trigger(rect, function() {
			spawnPoint.set_xy(rect.x + rect.w / 2, rect.y + rect.h / 2);

			var checkpointText:Text = new Text({
				depth: 120,
				text: "Checkpoint!",
				color: new Color(1, 1, 1, 1),
				font: Main.uiFont,
				pos: spawnPoint.clone(),
				align: TextAlign.center,
				point_size: 8,
				align_vertical: TextAlign.center
			});

			Actuate.tween(checkpointText.color, 3, { a: 0 }).onComplete(function() {
				checkpointText.destroy();
			});
		}));
	}

	function spawnFire(pos:Vector, direction:Float) {
		var particles:ParticleSystem = new ParticleSystem({
			name: 'Fire',
			name_unique: true,
			scene: playScene
		});
		particles.pos = pos.clone();
		particles.add_emitter({
			name: 'flames',
			emit_time: 0.05,
			emit_count: 1,
			direction: direction,
			direction_random: 0,
			speed: 3,
			speed_random: 0,
			end_speed: 0,
			life: 0.2,
			life_random: 0,
			rotation: 0,
			rotation_random: 0,
			end_rotation: 0,
			end_rotation_random: 0,
			rotation_offset: 0,
			pos_offset: new Vector(),
			pos_random: new Vector(2, 2),
			gravity: new Vector(),
			start_size: new Vector(8, 8),
			start_size_random: new Vector(),
			end_size: new Vector(4, 4),
			end_size_random: new Vector(),
			start_color: new Color(1, 1, 0, 1),
			end_color: new Color(1, 0, 0, 0),
			group: 5,
			depth: 90
		});

		var haloTexture:Texture = Luxe.resources.find_texture("assets/sprites/light.png");
		haloTexture.filter = FilterType.nearest;
		var halo:Sprite = new Sprite({
			name: 'halo',
			name_unique: true,
			pos: pos,
			size: new Vector(32, 32),
			texture: haloTexture,
			color: new Color(1, 1, 1, 0.2),
			scene: playScene,
			depth: 500
		});
		var rect:Rectangle = new Rectangle();
		switch(direction) {
			case 0: {
				rect.x = pos.x - 16;
				rect.y = pos.y - 8;
				rect.w = 20;
				rect.h = 16;
			}

			case 180: {
				rect.x = pos.x - 4;
				rect.y = pos.y - 8;
				rect.w = 20;
				rect.h = 16;
			}

			case 270: {
				rect.x = pos.x - 8;
				rect.y = pos.y - 4;
				rect.w = 16;
				rect.h = 20;
			}

			default: {
				rect.x = pos.x - 8;
				rect.y = pos.y - 16;
				rect.w = 16;
				rect.h = 20;
			}
		}
		particles.add(new components.Trigger(rect, burnFeathers));
	}

	function burnFeathers() {
		if(featherRockIsBurning) return;
		featherRockIsBurning = true;

		Main.musicManager.play("burnt");

		// go back to the spawn point
		featherRock.visible = false;
		featherRock.remove('LazyCameraFollow');
		featherRock.remove('LoseMagicOverTime');
		featherRock.remove('FeatherRockControls');
		cast(featherRock.get('FeatherRockPhysics'), FeatherRockPhysics).body.velocity.setxy(0, 0);

		// create a new burnt featherrock
		var featherRockTexture:Texture = Luxe.resources.find_texture("assets/sprites/featherrock.png");
		featherRockTexture.filter = FilterType.nearest;
		var rock:Sprite = new Sprite({
			name: 'deadrock',
			name_unique: true,
			pos: featherRock.pos.clone(),
			size: new Vector(16, 16),
			texture: featherRockTexture,
			scene: playScene
		});

		rock.add(new FeatherRockPhysics(PhysicsTypes.deadrock));
		rock.add(new components.LazyCameraFollow());

		var anim:SpriteAnimation = rock.add(new SpriteAnimation({ name: 'SpriteAnimation' }));
		anim.add_from_json_object(Luxe.resources.find_json('assets/sprites/featherrock.json').json);
		anim.animation = 'burnt';
		anim.play();
		
		Luxe.timer.schedule(1, function() {
			cast(featherRock.get('FeatherRockPhysics'), FeatherRockPhysics).body.position.setxy(spawnPoint.x, spawnPoint.y);
			cast(featherRock.get('FeatherRockPhysics'), FeatherRockPhysics).body.velocity.setxy(0, 0);
			featherRock.visible = true;
			Luxe.physics.nape.space.bodies.add(cast(featherRock.get('FeatherRockPhysics'), FeatherRockPhysics).body);
			rock.remove('LazyCameraFollow');
			featherRock.add(new components.LazyCameraFollow());
			featherRock.add(new components.LoseMagicOverTime(TweakConfig.magicDrainSpeed, burnFeathers));
			featherRock.add(new components.FeatherRockControls());
			featherRockIsBurning = false;
			Main.playerData.magic = TweakConfig.startMagic;
			Main.musicManager.play("wahwah");
			Main.playerData.magic = checkpointMagic;
		}, false);
	}
}