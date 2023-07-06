local utf8 = require("utf8")

local folderOfThisFile = (...):match("(.-)[^%.]+$")
local function drawSort(a,b) return a.y+a.h < b.y+b.h end


return {
            activeLayer=1,
            name="",
            size={width=love.graphics.getWidth(), height=love.graphics.getHeight()},
            objectTypes={},
            layers={},
            objects={},
            scale={x=1, y=1},
            path=love.filesystem.getSource(),
            binser=require(folderOfThisFile .. "binser"),
            zsort={},
            saveImages={},
            saveLookup={},
            directories={scenes="", layers="", sprites="", music=""},
           init=function(self, info)
                local dir=info.directories
                if dir~=nil then
                    if dir.scenes~=nil then self.directories.scenes=dir.scenes end
                    if dir.layers~=nil then self.directories.layers=dir.layers end
                    if dir.sprites~=nil then self.directories.sprites=dir.sprites end
                    if dir.music~=nil then self.directories.music=dir.music end
                end
                if info.scale~=nil then 
                    self:setScale(info.scale[1], info.scale[2]) 
                end
                self.canvas=love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())

                self.customFunc={}
                if info.functions~=nil then
                    info=info.functions 
                    if info.startGame~=nil then info.startGame(self) end
                    if info.init~=nil then self.customFunc.init=info.init end
                    if info.draw~=nil then self.customFunc.draw=info.draw end
                    if info.update~=nil then self.customFunc.update=info.update end
                    --layer functions, with similar update/etc. called per layer.
                    if info.layers~=nil then self.customFunc.layers=info.layers end
                end

                --preload scene music from scene folder.
                local files = love.filesystem.getDirectoryItems(self.directories.music)
                self.sceneMusic={}
                for i,file in ipairs(files) do
                    if string.find(file, ".mp3") or string.find(file, ".wav") or string.find(file, ".ogg") then
                        self.sceneMusic[#self.sceneMusic+1]={name=file, music=love.audio.newSource(self.directories.music .. "/" .. file, "stream")}
                    end
                end
                simpleScene:newScene({name="", x=0, y=0})
           end,
           setScale=function(self, scalex, scaley)
                self.scale={x=scalex, y=scaley}
            end,
            newScene=function(self, vars, loading)
                self:clean()
                self.name=vars.name
                if vars.x==nil then vars.x=0 end
                if vars.y==nil then vars.y=0 end

                self.x=vars.x
                self.y=vars.y

                if vars.gridSize~=nil then self.gridSize=vars.gridSize else self.gridSize=8 end
                if vars.scale~=nil then self.scale=vars.scale else self.scale={x=1, y=1} end

                self.music=vars.music
                if vars.activeLayer~=nil then self.activeLayer=vars.activeLayer else vars.activeLayer=1 end
                --first blank layer--
                if not loading then simpleScene:addLayer({x=0, y=0}) end
            end,
            clean=function(self)
                self.useGrid=false
                self.activeLayer=1
                self.scale={x=1, y=1}
                for i=#self.layers, -1 do self.layers[i]=nil end self.layers={}
                for i=#self.objects, -1 do self.objects[i]=nil end self.objects={}
            end,
            load=function(self, name)
                local data, len=self.binser.readFile(self.path .. "/" .. self.directories.scenes .. "/" .. name)
                data=data[1]
                self:newScene(data.scene, true)
                for i,v in ipairs(data.objects) do
                    self:addObject(v)
                end
                for i,v in ipairs(data.layers) do
                    self:addLayer(v)
                end
            end,
            setBackgroundImage=function(self, layer, img)
                self.layers[layer].imageName=img
                self.layers[layer].image=love.graphics.newImage(self.directories.layers .. "/" .. img)
                self.layers[layer].canvas=love.graphics.newCanvas(self.layers[layer].image:getWidth(), self.layers[layer].image:getHeight())
                self:moveLayer(layer, 0, 0)
            end,
            --add check here to see if x/y/w/h is obscured by layer over top of it.
            --if so, returns true, and layer id
            --if not, just returns false.
            addLayer=function(self, data, layer)
                if data.scroll==nil then
                    data.scroll={}
                    data.scroll.speed=1.0
                    data.scroll.constant={}
                    data.scroll.constant.x=false
                    data.scroll.constant.y=false
                end
                if data.scale==nil then data.scale=1 end
                if data.reverse==nil then data.reverse=false end 

                if data.alpha==nil then data.alpha=1.0 end 
                if data.x==nil then data.x=0 end
                if data.y==nil then data.y=0 end
                if data.visible==nil then data.visible=true end

                data.canvas=love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
                if layer==nil then 
                    data.id=#self.layers+1
                    self.layers[data.id]=data
                else
                    data.id=layer+1
                    table.insert(self.layers, data.id, data)
                end
                if data.image then
                    self:setBackgroundImage(data.id, data.image)
                end
            end,
            addObject=function(self, data)
                --sanity check
                if self.objectTypes[data.type]==nil then error(data.type .. " object type doesn't exist") end

                --add other variable data.
                local width, height=self.objectTypes[data.type].width,self.objectTypes[data.type].height

                data.width=width 
                data.height=height
                data.id=#self.objects+1
                data.scene=self.name
                self.objects[data.id]=data
                
                --if an init function is set in the object's template, use it.
                if self.objectTypes[data.type].init then  self.objectTypes[data.type]:init(self.objects[data.id], self) end
            end,
            changeObjectLayer=function(self, object, newLayer)
                if self.layers[newLayer]==nil then error("Tried to move object to layer #" .. newLayer ..",  but layer does not exist.") end
                --if an ID is passed and not the actual object, get the actual object.
                if type(object)=="number" then object=self.objects[object] end
                --we convert old coords on old layer to screen coords
                local x, y=self:layertoScreen(object.x, object.y, object.layer)
                --now we convert the screen coords to the new layer coords
                object.x, object.y=self:screenToLayer(x, y, newLayer)
                object.layer=newlayer
            end,
            deleteLayer=function(self, layer)
                table.remove(self.layers, layer)
                if layer==self.activeLayer then self.activeLayer=self.activeLayer-1 end
                --delete all objects on layer.
                for i,v in ipairs(self.objects) do
                    if v.layer==layer then self:deleteObject(i) end
                end
            end,
            deleteObject=function(self, objid)
                table.remove(self.objects, objid)
            end,
            update=function(self, dt)

                for i=1, #self.layers do
                    self:updateLayer(i, dt)
                    if self.customFunc.layers~=nil and self.customFunc.layers.update~=nil then self.customFunc.layers.update(self, self.layers[i], dt) end
                end

                for ob, object in ipairs(self.objects) do 
                    local type=self.objectTypes[object.type]
                    if type.update~=nil then type:update(object, self, dt) end                    
                end
                --zsorting...
                for i=#self.zsort, -1 do self.zsort=nil end 
                self.zsort={}
                for i,v in ipairs(self.objects) do
                    self.zsort[#self.zsort+1]={id=i, x=v.x, y=v.y, h=v.height, w=v.width}
                end

                --run custom functions.
                if self.customFunc.update~=nil then self.customFunc.update(self, dt) end

                table.sort(self.zsort, drawSort)
            end,
            updateLayer=function(self, layer, dt)
                local id=layer
                layer=self.layers[layer]
                local move={x=0, y=0}
                if layer.scroll.constant.x==true then
                    move.x=layer.scroll.speed
                end
                if layer.scroll.constant.y==true then
                    move.y=layer.scroll.speed
                end
                self:moveLayer(id, move.x, move.y)
            end,
            ---allow the dev to query layers and objects, in case they want
            --to use something other than the simpleScene's default system for drawing and updating.
            getLayers=function(self)
                return self.layers
            end,
            getLayer=function(self, layer)
                if self.layers[layer]==nil then error("Layer " .. layer .. " doesn't exist") end
                return self.layers[layer]
            end,
            getObjects=function(self, layerid)
                if layerid~=nil and self.layers[layerid]~=nil then
                    local objects={}
                    for i,v in ipairs(self.objects) do
                        if v.layer==layerid then
                            objects[#objects+1]=v
                        end
                    end
                    return objects
                else
                    return self.objects
                end
            end,
            getObject=function(self, id)
                if id==nil and self.objecs[id]==nil then 
                    error("Object id " .. id .. " doesn't exist.")
                else
                    return self.objects[id]
                end
            end,
            drawObjects=function(self, layer)

                for i,v in ipairs(self.zsort) do
                    local object=self.objects[v.id]
                    if object.layer==layer then
                            local type=self.objectTypes[object.type]
                            if type.draw~=nil then
                                    type:draw(object, self) 
                            elseif type.image~=nil then
                                love.graphics.draw(type.image, object.x, object.y)
                            end
                    end
                end
            end,
            drawLayer=function(self, layer)
                local c={}
                c[1], c[2], c[3], c[4]=love.graphics.getColor()
                local a=c[4]
                --if it's passing the layer number...
                if type(layer)~="table" then layer=self.layers[layer] end
                if layer.visible then
                        love.graphics.setCanvas(layer.canvas)
                        love.graphics.clear()


                        if layer.image~=nil then
                            if self.customFunc.layers~=nil and self.customFunc.layers.draw~=nil then 
                                self.customFunc.layers.draw(self, layer, 0, 0) 
                            else
                                love.graphics.draw(layer.image, 0, 0)
                            end
                        end

                        self:drawObjects(layer.id) 
                        love.graphics.setCanvas()

                        love.graphics.setColor(c[1], c[2], c[3], layer.alpha)
                        if layer.tiled==true and layer.image~=nil then
                                layer.canvas:setWrap("repeat", "repeat")
                                local quad = love.graphics.newQuad(-layer.x*(self.scale.x*layer.scale), -layer.y*(self.scale.y*layer.scale), love.graphics.getWidth(), love.graphics.getHeight(), layer.image:getWidth(), layer.image:getHeight())	
                                love.graphics.draw(layer.canvas, quad, 0, 0, 0, (self.scale.x*layer.scale), (self.scale.y*layer.scale))
                        else
                            local x, y=(layer.scroll.speed*layer.scale)*self.x, (layer.scroll.speed*layer.scale)*self.y
                            love.graphics.draw(layer.canvas, (x*-1)+(layer.x*(self.scale.x*layer.scale)), (y*-1)+(layer.y*(self.scale.y*layer.scale)), 0, self.scale.x*layer.scale, self.scale.y*layer.scale)
                        end
                        love.graphics.setColor(c[1], c[2], c[3], c[4])
                end
            end,
            --precise placement.
            placeCamera=function(self, x, y)
                --this makes sure when it's placed that the sublayers are moved correctly
                --by finding the diference between current location and new location.
                self:moveCamera(x-self.x, y-self.y)
            end,
            --relative movement.
            moveCamera=function(self, x, y)
                    self.x=math.floor(self.x+x)
                    self.y=math.floor(self.y+y)
            end,
            
            cameraClampLayer=function(self, layer)
                local layer=self.layers[layer]
                local scale=(layer.scale*self.scale.x)
                local screen={x=(love.graphics.getWidth()/scale), y=(love.graphics.getHeight()/scale)}
                local edges={x=layer.x*scale, y=(layer.y-scale)*scale, w=screen.x-(layer.canvas:getWidth()/scale), h=screen.y-(layer.canvas:getHeight()/scale)}

                if self.x<edges.x then self.x=edges.x end
                if self.y<edges.y then self.y=edges.y end
                if self.x>edges.x+edges.w then self.x=edges.x+edges.w end
                if self.y>edges.y+edges.h then self.y=edges.y+edges.h end
            end,
            cameraFollowObject=function(self, obj)
                if type(obj)=="number" then obj=self.objects[obj] end
                local layer=self.layers[obj.layer]
                local center={x=(love.graphics.getWidth()/(self.scale.x*layer.scale))/2, y=(love.graphics.getHeight()/(self.scale.y*layer.scale))/2}

                simpleScene:placeCamera((((obj.x+(obj.width/2))-center.x)+layer.x)*(self.scale.x*layer.scale), (((obj.y+obj.height/2)-center.y)+layer.y)*(self.scale.y*layer.scale))
            end,
            sceneToScreen=function(self, x, y)
                x=x+self.x
                y=y+self.y
                x=x*self.scale.x
                y=y*self.scale.y
                return x, y
            end,
            screenToScene=function(self, x, y)
                x=x/self.scale.x
                y=y/self.scale.y
                x=x-self.x
                y=y-self.y
                return x, y
            end,
            screenToLayer=function(self, layer, x, y)
                local l=self.layers[layer]
                local scale=self.scale.x*l.scale
                x=x-l.x 
                y=y-l.y 
                x=x/scale 
                y=y/scale

                return x, y     
            end,
            layertoScreen=function(self, layer, x, y)
                local layer=self.layers[layer]
                local scale=(self.scale.x*layer.scale)
                x=(x*scale)+(layer.x*scale)
                y=(y*scale)+(layer.y*scale)
                return x, y
            end,
            --amount to move.
            moveObject=function(self, obj, x, y)
                local layer=self.layers[obj.layer]
                local tx=obj.x+x 
                local ty=obj.y+y

                obj.moveX=nil 
                obj.moveY=nil
                if tx>0 and tx+obj.width<layer.canvas:getWidth() then 
                    obj.moveX=x
                    obj.x=tx 
                end
                if ty>0 and ty+obj.height<layer.canvas:getHeight() then 
                    obj.moveY=y
                    obj.y=ty
                end
            end,
            moveLayer=function(self, layer, x, y)
                local layer=self.layers[layer]
                local move={x=layer.scroll.speed*x, y=layer.scroll.speed*y}
                if layer.reverse then 
                    move.x=move.x*-1
                    move.y=move.y*-1
                end
 
                layer.x=layer.x+(move.x)
                layer.y=layer.y+(move.y)
            end,
            stopAllMusic=function(self)
                for i,v in ipairs(self.sceneMusic) do
                    v.music:stop()
                end
                self.playing=false
            end,
            --loop plays the music set for this scene.
            playMusic=function(self)
                self:stopAllMusic()
                if self.music~=nil and self.music.music~=nil and self.sceneMusic[self.music.music]~=nil then
                    self.sceneMusic[self.music.music].music:setLooping(true)
                    self.sceneMusic[self.music.music].music:play()
                    self.playing=true
                end
            end,
            draw=function(self, x, y)
                if x==nil then x=self.x end
                if y==nil then y=self.y end


                for il,layer in ipairs(self.layers) do 
                        self:drawLayer(layer)
                end
                if self.customFunc.draw~=nil then self.customFunc.draw(self) end
            end,
            addObjectType=function(self, type)
                if type.image~=nil then 
                    type.imageName=type.image
                    type.image=love.graphics.newImage(self.directories.sprites .. type.image) 
                end
                if type.width==nil then type.width=type.image:getWidth() end
                if type.height==nil then type.height=type.image:getHeight() end
  
                self.objectTypes[type.type]=type
            end,
}